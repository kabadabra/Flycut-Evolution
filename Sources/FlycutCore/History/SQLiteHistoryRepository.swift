import Foundation
import SQLite3
import Darwin

public actor SQLiteHistoryRepository: HistoryRepository, ImageAssetRepository {
    nonisolated(unsafe) private let database: OpaquePointer
    private let url: URL?
    private let permissionMaintenance: @Sendable (URL) throws -> Void
    private let metadataStep: @Sendable (OpaquePointer?) -> Int32

    public init(url: URL) throws {
        try self.init(url: url, permissionMaintenance: Self.restrictPermissions, metadataStep: sqlite3_step)
    }

    internal init(
        url: URL,
        permissionMaintenance: @escaping @Sendable (URL) throws -> Void,
        metadataStep: @escaping @Sendable (OpaquePointer?) -> Int32
    ) throws {
        self.url = url
        self.permissionMaintenance = permissionMaintenance
        self.metadataStep = metadataStep
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw HistoryError.database("Unable to create history database") }
        guard Darwin.fchmod(descriptor, 0o600) == 0 else {
            Darwin.close(descriptor)
            throw HistoryError.database("Unable to protect history database")
        }
        Darwin.close(descriptor)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            defer { if let handle { sqlite3_close(handle) } }
            throw HistoryError.database("Unable to open history database")
        }
        database = handle
        do {
            try Self.execute(handle, "PRAGMA journal_mode=WAL")
            try Self.execute(handle, "PRAGMA foreign_keys=ON")
            let version = try Self.schemaVersion(handle)
            guard version <= 5 else { throw HistoryError.unsupportedSchema(version) }
            if version == 0 {
                try Self.execute(handle, "BEGIN IMMEDIATE")
                do {
                    try Self.execute(handle, "CREATE TABLE IF NOT EXISTS clips (id TEXT PRIMARY KEY, text TEXT NOT NULL, pasteboard_type TEXT NOT NULL, source_app_name TEXT, source_bundle_url TEXT, captured_at REAL, collection TEXT NOT NULL CHECK(collection IN ('recent','favorite')), position INTEGER NOT NULL, formatted_rtf BLOB, favorite_metadata BLOB)")
                    try Self.execute(handle, "CREATE INDEX IF NOT EXISTS clips_order ON clips(collection, position)")
                    try Self.execute(handle, "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                    try Self.execute(handle, "PRAGMA user_version=3")
                    try Self.restrictPermissions(url)
                    try Self.execute(handle, "COMMIT")
                } catch {
                    try? Self.execute(handle, "ROLLBACK")
                    throw error
                }
            } else if version == 1 || version == 2 {
                try Self.execute(handle, "BEGIN IMMEDIATE")
                do {
                    if version == 1 { try Self.execute(handle, "ALTER TABLE clips ADD COLUMN formatted_rtf BLOB") }
                    try Self.execute(handle, "ALTER TABLE clips ADD COLUMN favorite_metadata BLOB")
                    try Self.execute(handle, "PRAGMA user_version=3")
                    try Self.restrictPermissions(url)
                    try Self.execute(handle, "COMMIT")
                } catch {
                    try? Self.execute(handle, "ROLLBACK")
                    throw error
                }
            } else {
                try Self.restrictPermissions(url)
            }
            if version < 4 {
                try Self.execute(handle, "BEGIN IMMEDIATE")
                do {
                    try Self.execute(handle, "ALTER TABLE clips ADD COLUMN image_metadata BLOB")
                    try Self.execute(handle, "ALTER TABLE clips ADD COLUMN source_bundle_identifier TEXT")
                    try Self.execute(handle, "CREATE TABLE image_assets (hash TEXT PRIMARY KEY, png BLOB NOT NULL)")
                    try Self.execute(handle, "PRAGMA user_version=4")
                    try Self.execute(handle, "COMMIT")
                } catch { try? Self.execute(handle, "ROLLBACK"); throw error }
            }
            if version < 5 {
                try Self.execute(handle, "BEGIN IMMEDIATE")
                do {
                    try Self.execute(handle, "ALTER TABLE clips ADD COLUMN file_metadata BLOB")
                    try Self.execute(handle, "PRAGMA user_version=5")
                    try Self.execute(handle, "COMMIT")
                } catch { try? Self.execute(handle, "ROLLBACK"); throw error }
            }
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    public init(inMemory: Void = ()) throws {
        url = nil
        permissionMaintenance = Self.restrictPermissions
        metadataStep = sqlite3_step
        var handle: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            defer { if let handle { sqlite3_close(handle) } }
            throw HistoryError.database("Unable to open in-memory history database")
        }
        database = handle
        do {
            try Self.execute(handle, "CREATE TABLE clips (id TEXT PRIMARY KEY, text TEXT NOT NULL, pasteboard_type TEXT NOT NULL, source_app_name TEXT, source_bundle_url TEXT, captured_at REAL, collection TEXT NOT NULL CHECK(collection IN ('recent','favorite')), position INTEGER NOT NULL, formatted_rtf BLOB, favorite_metadata BLOB)")
            try Self.execute(handle, "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try Self.execute(handle, "ALTER TABLE clips ADD COLUMN image_metadata BLOB")
            try Self.execute(handle, "ALTER TABLE clips ADD COLUMN source_bundle_identifier TEXT")
            try Self.execute(handle, "CREATE TABLE image_assets (hash TEXT PRIMARY KEY, png BLOB NOT NULL)")
            try Self.execute(handle, "ALTER TABLE clips ADD COLUMN file_metadata BLOB")
            try Self.execute(handle, "PRAGMA user_version=5")
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    /// Inspect durable migration metadata without reading clipping rows, creating
    /// a database, changing permissions, or enabling a writable connection.
    public static func migrationMarker(at url: URL) throws -> MigrationMarker? {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return nil }
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        defer { if let handle { sqlite3_close(handle) } }
        guard status == SQLITE_OK, let handle else { throw HistoryError.database("Unable to inspect migration metadata") }
        let statement = try prepare(handle, "SELECT value FROM metadata WHERE key='migration'")
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_DONE: return nil
        case SQLITE_ROW:
            guard let value = text(statement, 0) else { throw HistoryError.database("Invalid migration metadata") }
            return try JSONDecoder().decode(MigrationMarker.self, from: Data(value.utf8))
        default: throw HistoryError.database("Unable to read migration metadata")
        }
    }

    public func snapshot() throws -> HistorySnapshot { try readSnapshot() }

    public func apply(_ change: HistoryChange) throws -> HistorySnapshot {
        try update { try Self.mutate(&$0, change) }
    }

    public func update(_ body: @Sendable (inout HistorySnapshot) throws -> Void) throws -> HistorySnapshot {
        try transaction {
            var current = try readSnapshot()
            try body(&current)
            try writeSnapshot(current)
            try removeUnreferencedAssets()
            return try readSnapshot()
        }
    }

    public func replaceAll(_ snapshot: HistorySnapshot) throws {
        try transaction { try writeSnapshot(snapshot); try removeUnreferencedAssets() }
    }

    private static func mutate(_ snapshot: inout HistorySnapshot, _ change: HistoryChange) throws {
        switch change {
        case .insert(let clip):
            guard !snapshot.recent.contains(where: { $0.id == clip.id }), !snapshot.favorites.contains(where: { $0.id == clip.id }) else { throw HistoryError.duplicateID }
            switch clip.collection {
            case .recent: snapshot.recent.insert(clip, at: 0)
            case .favorite: snapshot.favorites.insert(clip, at: 0)
            }
        case .delete(let id):
            let count = snapshot.recent.count + snapshot.favorites.count
            snapshot.recent.removeAll { $0.id == id }
            snapshot.favorites.removeAll { $0.id == id }
            guard snapshot.recent.count + snapshot.favorites.count < count else { throw HistoryError.missingClip }
        case .moveToTop(let id):
            if let index = snapshot.recent.firstIndex(where: { $0.id == id }) {
                snapshot.recent.insert(snapshot.recent.remove(at: index), at: 0)
            } else if let index = snapshot.favorites.firstIndex(where: { $0.id == id }) {
                snapshot.favorites.insert(snapshot.favorites.remove(at: index), at: 0)
            } else { throw HistoryError.missingClip }
        case .clear(let collection):
            switch collection {
            case .recent: snapshot.recent = []
            case .favorite: snapshot.favorites = []
            }
        case .batch(let changes):
            for item in changes { try mutate(&snapshot, item) }
        }
    }

    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let result = try work()
            if let url { try permissionMaintenance(url) }
            try Self.execute(database, "COMMIT")
            return result
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    private func writeSnapshot(_ snapshot: HistorySnapshot) throws {
        try Self.execute(database, "DELETE FROM clips")
        var seen = Set<UUID>()
        for (kind, list) in [(CollectionKind.recent, snapshot.recent), (.favorite, snapshot.favorites)] {
            for (position, clip) in list.enumerated() {
                guard clip.collection == kind else { throw HistoryError.invalidCollection }
                guard seen.insert(clip.id).inserted else { throw HistoryError.duplicateID }
                try insert(clip, position: position)
            }
        }
        try Self.execute(database, "DELETE FROM metadata WHERE key='migration'")
        if let marker = snapshot.migration {
            let data = try JSONEncoder().encode(marker)
            let value = String(decoding: data, as: UTF8.self)
            let statement = try Self.prepare(database, "INSERT INTO metadata(key,value) VALUES('migration',?)")
            defer { sqlite3_finalize(statement) }
            try Self.bind(value, to: statement, at: 1)
            try Self.step(statement, database)
        }
    }

    private func insert(_ clip: Clip, position: Int) throws {
        let statement = try Self.prepare(database, "INSERT INTO clips(id,text,pasteboard_type,source_app_name,source_bundle_url,captured_at,collection,position,formatted_rtf,favorite_metadata,image_metadata,source_bundle_identifier,file_metadata) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(statement) }
        try Self.bind(clip.id.uuidString, to: statement, at: 1)
        try Self.bind(clip.text, to: statement, at: 2)
        try Self.bind(clip.pasteboardType, to: statement, at: 3)
        try Self.bind(clip.sourceAppName, to: statement, at: 4)
        try Self.bind(clip.sourceBundleURL, to: statement, at: 5)
        if let date = clip.capturedAt { sqlite3_bind_double(statement, 6, date.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 6) }
        try Self.bind(clip.collection.rawValue, to: statement, at: 7)
        sqlite3_bind_int64(statement, 8, Int64(position))
        try Self.bind(clip.formattedRTF, to: statement, at: 9)
        try Self.bind(try clip.favoriteMetadata.map { try JSONEncoder().encode($0) }, to: statement, at: 10)
        try Self.bind(try clip.image.map { try JSONEncoder().encode($0) }, to: statement, at: 11)
        try Self.bind(clip.sourceBundleIdentifier, to: statement, at: 12)
        guard clip.files.map({ !$0.isEmpty && $0.count <= 100 }) ?? true else { throw HistoryError.database("Invalid file references") }
        try Self.bind(try clip.files.map { try JSONEncoder().encode($0) }, to: statement, at: 13)
        if let image = clip.image {
            guard image.isValid, try imageByteCount(for: image.assetHash) == image.byteCount else { throw HistoryError.database("Image asset is missing or invalid") }
        }
        try Self.step(statement, database)
    }

    private func readSnapshot() throws -> HistorySnapshot {
        let statement = try Self.prepare(database, "SELECT id,text,pasteboard_type,source_app_name,source_bundle_url,captured_at,collection,position,formatted_rtf,favorite_metadata,image_metadata,source_bundle_identifier,file_metadata FROM clips ORDER BY collection,position")
        defer { sqlite3_finalize(statement) }
        var recent: [Clip] = []
        var favorites: [Clip] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw HistoryError.database("Unable to read history") }
            guard let idText = Self.text(statement, 0), let id = UUID(uuidString: idText), let text = Self.text(statement, 1), let type = Self.text(statement, 2), let kindText = Self.text(statement, 6), let kind = CollectionKind(rawValue: kindText) else { throw HistoryError.database("Invalid history record") }
            let date = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let clip = Clip(id: id, text: text, pasteboardType: type, sourceAppName: Self.text(statement, 3), sourceBundleURL: Self.text(statement, 4), capturedAt: date, collection: kind, order: Int(sqlite3_column_int64(statement, 7)), formattedRTF: Self.blob(statement, 8), favoriteMetadata: try Self.blob(statement, 9).map { try JSONDecoder().decode(FavoriteMetadata.self, from: $0) }, image: try Self.blob(statement, 10).map { try JSONDecoder().decode(ClipImage.self, from: $0) }, sourceBundleIdentifier: Self.text(statement, 11), files: try Self.blob(statement, 12).map { try JSONDecoder().decode([ClipFile].self, from: $0) })
            switch kind {
            case .recent: recent.append(clip)
            case .favorite: favorites.append(clip)
            }
        }
        let metadata = try Self.prepare(database, "SELECT value FROM metadata WHERE key='migration'")
        defer { sqlite3_finalize(metadata) }
        var marker: MigrationMarker?
        switch metadataStep(metadata) {
        case SQLITE_ROW:
            guard let value = Self.text(metadata, 0) else { throw HistoryError.database("Invalid migration metadata") }
            marker = try JSONDecoder().decode(MigrationMarker.self, from: Data(value.utf8))
        case SQLITE_DONE:
            break
        default:
            throw HistoryError.database("Unable to read migration metadata")
        }
        return HistorySnapshot(recent: recent, favorites: favorites, migration: marker)
    }

    private func imageByteCount(for hash: String) throws -> Int? {
        let statement = try Self.prepare(database, "SELECT length(png) FROM image_assets WHERE hash=?")
        defer { sqlite3_finalize(statement) }
        try Self.bind(hash, to: statement, at: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw HistoryError.database("Unable to inspect image asset") }
        return Int(sqlite3_column_int64(statement, 0))
    }
    public func imageData(for hash: String) throws -> Data? {
        let statement = try Self.prepare(database, "SELECT png FROM image_assets WHERE hash=?")
        defer { sqlite3_finalize(statement) }
        try Self.bind(hash, to: statement, at: 1)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw HistoryError.database("Unable to read image asset") }
        return Self.blob(statement, 0)
    }
    private func insertAsset(_ asset: ImageAsset) throws {
        guard !asset.png.isEmpty, asset.png.count <= 16 * 1024 * 1024 else { throw HistoryError.database("Invalid image asset size") }
        if let existing = try imageData(for: asset.hash) {
            guard existing == asset.png else { throw HistoryError.database("Image hash collision") }
            return
        }
        let statement = try Self.prepare(database, "INSERT INTO image_assets(hash,png) VALUES(?,?)")
        defer { sqlite3_finalize(statement) }
        try Self.bind(asset.hash, to: statement, at: 1)
        try Self.bind(asset.png, to: statement, at: 2)
        try Self.step(statement, database)
    }
    public func exportAssets(for snapshot: HistorySnapshot) throws -> [ImageAsset] {
        try Set((snapshot.recent + snapshot.favorites).compactMap { $0.image?.assetHash }).map { hash in
            guard let png = try imageData(for: hash) else { throw HistoryError.database("Image asset missing") }
            return ImageAsset(hash: hash, png: png)
        }
    }
    public func replaceAll(_ snapshot: HistorySnapshot, assets: [ImageAsset], expected: HistorySnapshot? = nil) throws {
        try transaction {
            if let expected { guard try readSnapshot() == expected else { throw HistoryError.staleSnapshot } }
            for asset in assets { try insertAsset(asset) }
            try writeSnapshot(snapshot); try removeUnreferencedAssets()
        }
    }
    /// Reject an oversized remote collection as a unit. No local eviction means
    /// a smaller receiver cannot infer and upload deletions on another Mac.
    public func importSynced(_ snapshot: HistorySnapshot, assets: [ImageAsset], budgetBytes: Int) throws {
        try transaction {
            let incoming = Dictionary(assets.map { ($0.hash, $0.png.count) }, uniquingKeysWith: { a, _ in a })
            let hashes = Set((snapshot.recent + snapshot.favorites).compactMap { $0.image?.assetHash })
            var total = 0
            for hash in hashes {
                guard let count = try incoming[hash] ?? imageByteCount(for: hash) else { throw HistoryError.database("Image asset missing") }
                total += count
            }
            guard total <= budgetBytes else { throw HistoryError.database("Synced images exceed this Mac's storage limit. Increase the image storage limit to receive this collection. Existing history is safe.") }
            for asset in assets { try insertAsset(asset) }
            try writeSnapshot(snapshot); try removeUnreferencedAssets()
        }
    }
    public func applyImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int, recentCapacity: Int = 100_000) throws -> HistorySnapshot {
        try applyImage(asset, clip: clip, budgetBytes: budgetBytes, recentCapacity: recentCapacity, archive: nil)
    }
    public func applyImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int, recentCapacity: Int, archive: EvictionArchive?) throws -> HistorySnapshot {
        try transaction {
            guard clip.image?.assetHash == asset.hash else { throw HistoryError.database("Image identity mismatch") }
            var snapshot = try readSnapshot()
            let before = snapshot
            let sizes = Dictionary((snapshot.recent + snapshot.favorites).compactMap { $0.image }.map { ($0.assetHash, $0.byteCount) }, uniquingKeysWith: { a, _ in a })
            let evictions = Set(try ImageBudgetPolicy.planEvictions(snapshot: snapshot, assetSizes: sizes, incomingHash: asset.hash, incomingBytes: asset.png.count, budgetBytes: budgetBytes))
            snapshot.recent.removeAll { evictions.contains($0.id) || ($0.image?.assetHash == asset.hash && $0.sourceBundleIdentifier == clip.sourceBundleIdentifier && $0.files == clip.files) }
            snapshot.recent.insert(clip, at: 0)
            if snapshot.recent.count > max(1, recentCapacity) { snapshot.recent = Array(snapshot.recent.prefix(max(1, recentCapacity))) }
            if let archive {
                let retained = Set(snapshot.recent.map(\.id))
                let victims = before.recent.filter { !retained.contains($0.id) && ($0.image?.assetHash != asset.hash || $0.sourceBundleIdentifier != clip.sourceBundleIdentifier || $0.files != clip.files) }
                var data: [String: Data] = [:]
                for victim in victims {
                    if let hash = victim.image?.assetHash { data[hash] = try imageData(for: hash) }
                }
                try archive.save(victims, imageAssets: data)
            }
            try insertAsset(asset); try writeSnapshot(snapshot); try removeUnreferencedAssets()
            return try readSnapshot()
        }
    }
    public func trimImageBudget(to budget: Int, archive: EvictionArchive? = nil) throws -> Bool {
        try transaction {
            var snapshot = try readSnapshot()
            let before = snapshot
            func bytes() -> Int {
                Dictionary((snapshot.recent + snapshot.favorites).compactMap { $0.image }.map { ($0.assetHash, $0.byteCount) }, uniquingKeysWith: { a, _ in a }).values.reduce(0, +)
            }
            while bytes() > budget, let index = snapshot.recent.lastIndex(where: { $0.image != nil }) { snapshot.recent.remove(at: index) }
            if let archive {
                let retained = Set(snapshot.recent.map(\.id))
                let victims = before.recent.filter { !retained.contains($0.id) }
                var assets: [String: Data] = [:]
                for victim in victims { if let hash = victim.image?.assetHash { assets[hash] = try imageData(for: hash) } }
                try archive.save(victims, imageAssets: assets)
            }
            try writeSnapshot(snapshot); try removeUnreferencedAssets()
            return bytes() <= budget
        }
    }
    private func removeUnreferencedAssets() throws {
        let referenced = Set((try readSnapshot()).recent.compactMap { $0.image?.assetHash } + (try readSnapshot()).favorites.compactMap { $0.image?.assetHash })
        let statement = try Self.prepare(database, "SELECT hash FROM image_assets")
        var unused: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { if let hash = Self.text(statement, 0), !referenced.contains(hash) { unused.append(hash) } }
        sqlite3_finalize(statement)
        for hash in unused {
            let deletion = try Self.prepare(database, "DELETE FROM image_assets WHERE hash=?")
            defer { sqlite3_finalize(deletion) }
            try Self.bind(hash, to: deletion, at: 1); try Self.step(deletion, database)
        }
    }

    private static func schemaVersion(_ database: OpaquePointer) throws -> Int {
        let statement = try prepare(database, "PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw HistoryError.database("Unable to read schema version") }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func restrictPermissions(_ url: URL) throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw HistoryError.database("History database operation failed") }
    }

    private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw HistoryError.database("Unable to prepare history database operation") }
        return statement
    }

    private static func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        guard let value else { sqlite3_bind_null(statement, index); return }
        let result = value.utf8CString.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text(statement, index, buffer.baseAddress, Int32(buffer.count - 1), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw HistoryError.database("Unable to write history") }
    }

    private static func bind(_ value: Data?, to statement: OpaquePointer, at index: Int32) throws {
        guard let value else { sqlite3_bind_null(statement, index); return }
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw HistoryError.database("Unable to write history") }
    }

    private static func step(_ statement: OpaquePointer, _ database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryError.database("Unable to write history") }
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }

    private static func blob(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let pointer = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}
