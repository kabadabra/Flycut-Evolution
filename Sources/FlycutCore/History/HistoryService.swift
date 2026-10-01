import Foundation
import Darwin

public actor HistoryService {
    private struct DuplicateKey: Hashable {
        let text: String
        let source: String

        init(_ clip: Clip) {
            text = clip.contentIdentity
            if let name = clip.sourceAppName { source = "name:\(name)" }
            else if let url = clip.sourceBundleURL { source = "url:\(url)" }
            else { source = "unknown" }
        }
    }
    private let repository: any HistoryRepository
    private let recentCapacity: Int
    private let favoriteCapacity: Int
    private let archive: EvictionArchive?
    private let archiveRecents: Bool
    private let archiveFavorites: Bool

    public init(repository: any HistoryRepository, recentCapacity: Int = 40, favoriteCapacity: Int = 40, archive: EvictionArchive? = nil, archiveRecents: Bool = false, archiveFavorites: Bool = false) {
        self.archive = archive; self.archiveRecents = archiveRecents; self.archiveFavorites = archiveFavorites
        self.repository = repository
        self.recentCapacity = max(0, recentCapacity)
        self.favoriteCapacity = max(0, favoriteCapacity)
    }

    public func backupSnapshot(_ snapshot: HistorySnapshot, assets: [ImageAsset], to url: URL) throws {
        try Self.writePrivateBackup(snapshot, to: url, assets: assets)
    }

    /// Apply an explicit configured limit immediately, backing up before eviction.
    @discardableResult
    public func enforceCapacities(backupTo url: URL? = nil) async throws -> HistorySnapshot {
        let before = try await repository.snapshot()
        guard before.recent.count > recentCapacity || before.favorites.count > favoriteCapacity else { return before }
        let assets = try await (repository as? any ImageAssetRepository)?.exportAssets(for: before) ?? []
        let bytes = Dictionary(uniqueKeysWithValues: assets.map { ($0.hash, $0.png) })
        let recentLimit = recentCapacity, favoriteLimit = favoriteCapacity
        let recentArchive = archiveRecents ? archive : nil, favoriteArchive = archiveFavorites ? archive : nil
        return try await repository.update { current in
            guard current == before else { throw HistoryError.staleSnapshot }
            if let url { try Self.writePrivateBackup(current, to: url, assets: assets) }
            try recentArchive?.save(Array(current.recent.dropFirst(recentLimit)), imageAssets: bytes)
            try favoriteArchive?.save(Array(current.favorites.dropFirst(favoriteLimit)), imageAssets: bytes)
            current.recent = Array(current.recent.prefix(recentLimit))
            current.favorites = Array(current.favorites.prefix(favoriteLimit))
        }
    }

    @discardableResult
    public func captureImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int) async throws -> HistorySnapshot {
        guard let images = repository as? SQLiteHistoryRepository else { throw HistoryError.database("Image storage is unavailable") }
        return try await images.applyImage(asset, clip: clip, budgetBytes: budgetBytes, recentCapacity: recentCapacity,
                                          archive: archiveRecents ? archive : nil)
    }

    @discardableResult
    public func capture(_ clip: Clip) async throws -> HistorySnapshot {
        let capacity = recentCapacity
        let archive = archiveRecents ? archive : nil
        let imageAssets = try await assetsForExport(collection: .recent, capacity: capacity, enabled: archive != nil)
        return try await repository.update { current in
            if clip.contentKind == .text && clip.isUniversalControlSource && current.recent.contains(where: { $0.contentKind == .text && $0.text == clip.text }) { return }
            if clip.contentKind == .text && !clip.isUniversalControlSource {
                current.recent.removeAll { $0.contentKind == .text && $0.isUniversalControlSource && $0.text == clip.text }
            }
            let key = DuplicateKey(clip)
            let retainedID = current.recent.first(where: { DuplicateKey($0) == key })?.id ?? clip.id
            current.recent.removeAll { DuplicateKey($0) == key }
            current.recent.insert(Clip(id: retainedID, text: clip.text, pasteboardType: clip.pasteboardType,
                                       sourceAppName: clip.sourceAppName, sourceBundleURL: clip.sourceBundleURL,
                                       capturedAt: clip.capturedAt, collection: .recent, order: 0,
                                       formattedRTF: clip.formattedRTF, image: clip.image, sourceBundleIdentifier: clip.sourceBundleIdentifier, files: clip.files), at: 0)
            if current.recent.count > capacity {
                try archive?.save(Array(current.recent.suffix(current.recent.count - capacity)), imageAssets: imageAssets)
                current.recent.removeLast(current.recent.count - capacity)
            }
        }
    }

    @discardableResult
    public func normalizeRecents(backupTo backupURL: URL? = nil) async throws -> HistorySnapshot {
        let before = try await repository.snapshot()
        var seenBefore = Set<DuplicateKey>()
        let ordinaryTexts = Set(before.recent.filter { !$0.isUniversalControlSource && $0.contentKind == .text }.map(\.text))
        let hasDuplicates = before.recent.contains { !seenBefore.insert(DuplicateKey($0)).inserted || ($0.contentKind == .text && $0.isUniversalControlSource && ordinaryTexts.contains($0.text)) }
        let assets: [ImageAsset]
        if backupURL != nil, hasDuplicates, let images = repository as? any ImageAssetRepository { assets = try await images.exportAssets(for: before) } else { assets = [] }
        return try await repository.update { current in
            let otherSourceTexts = Set(current.recent.filter { !$0.isUniversalControlSource && $0.contentKind == .text }.map(\.text))
            var seen = Set<DuplicateKey>()
            let retained = current.recent.filter {
                guard $0.contentKind != .text || !$0.isUniversalControlSource || !otherSourceTexts.contains($0.text) else { return false }
                return seen.insert(DuplicateKey($0)).inserted
            }
            guard retained.count != current.recent.count else { return }
            if let backupURL { try Self.writePrivateBackup(current, to: backupURL, assets: assets) }
            current.recent = retained
        }
    }

    private static func writePrivateBackup(_ snapshot: HistorySnapshot, to url: URL, assets: [ImageAsset]) throws {
        let imageHashes = Set((snapshot.recent + snapshot.favorites).compactMap { $0.image?.assetHash })
        guard imageHashes.isSubset(of: Set(assets.map(\.hash))) else { throw HistoryError.database("Image backup data unavailable") }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object["imageAssets"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assets))
        let data = try JSONSerialization.data(withJSONObject: object)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HistoryError.database("Unable to create private history backup") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public func updateRecognition(id: UUID, assetHash: String, text: String?, state: ImageRecognitionState) async throws -> HistorySnapshot {
        try await repository.update { snapshot in
            func updated(_ clip: Clip) -> Clip {
                guard clip.id == id, var image = clip.image, image.assetHash == assetHash else { return clip }
                image.recognizedText = text; image.recognitionState = state
                return Clip(id: clip.id, text: clip.text, pasteboardType: clip.pasteboardType, sourceAppName: clip.sourceAppName, sourceBundleURL: clip.sourceBundleURL, capturedAt: clip.capturedAt, collection: clip.collection, order: clip.order, formattedRTF: clip.formattedRTF, favoriteMetadata: clip.favoriteMetadata, image: image, sourceBundleIdentifier: clip.sourceBundleIdentifier, files: clip.files)
            }
            guard (snapshot.recent + snapshot.favorites).contains(where: { $0.id == id && $0.image?.assetHash == assetHash }) else { throw HistoryError.missingClip }
            snapshot.recent = snapshot.recent.map(updated); snapshot.favorites = snapshot.favorites.map(updated)
        }
    }
    public func search(_ query: String) async throws -> [Clip] {
        let before = try await repository.snapshot()
        guard !query.isEmpty else { return before.recent + before.favorites }
        return (before.recent + before.favorites).filter { $0.text.localizedStandardContains(query) }
    }

    @discardableResult
    public func favorite(id: UUID) async throws -> HistorySnapshot {
        let capacity = favoriteCapacity
        let archive = archiveFavorites ? archive : nil
        let imageAssets = try await assetsForExport(collection: .favorite, capacity: capacity, enabled: archive != nil)
        return try await repository.update { current in
            guard let selected = current.recent.first(where: { $0.id == id }) else { throw HistoryError.missingClip }
            current.favorites.insert(Clip(id: selected.id, text: selected.text, pasteboardType: selected.pasteboardType, sourceAppName: selected.sourceAppName, sourceBundleURL: selected.sourceBundleURL, capturedAt: selected.capturedAt, collection: .favorite, order: 0, formattedRTF: selected.formattedRTF, favoriteMetadata: .init(rank: 0), image: selected.image, sourceBundleIdentifier: selected.sourceBundleIdentifier, files: selected.files), at: 0)
            if current.favorites.count > capacity {
                try archive?.save(Array(current.favorites.suffix(current.favorites.count - capacity)), imageAssets: imageAssets)
                current.favorites.removeLast(current.favorites.count - capacity)
            }
            current.recent.removeAll { $0.id == id }
            Self.rankFavorites(&current)
        }
    }

    @discardableResult
    public func updateFavorite(id: UUID, edit: FavoriteEdit) async throws -> HistorySnapshot {
        guard edit.name.count <= 200, edit.shortcut.map({ (1...9).contains($0) }) ?? true else { throw HistoryError.invalidFavorite }
        return try await repository.update { current in
            guard let index = current.favorites.firstIndex(where: { $0.id == id }) else { throw HistoryError.missingClip }
            if let slot = edit.shortcut,
               current.favorites.contains(where: { $0.id != id && $0.favoriteMetadata?.shortcut == slot }) { throw HistoryError.shortcutInUse }
            let old = current.favorites[index]
            guard old.contentKind != .text || !edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HistoryError.invalidFavorite }
            let changedText = old.contentKind == .text && old.text != edit.text
            let name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            current.favorites[index] = Clip(id: old.id, text: old.contentKind == .text ? edit.text : old.text,
                pasteboardType: changedText ? "public.utf8-plain-text" : old.pasteboardType,
                sourceAppName: old.sourceAppName, sourceBundleURL: old.sourceBundleURL, capturedAt: old.capturedAt,
                collection: .favorite, order: old.order, formattedRTF: changedText ? nil : old.formattedRTF,
                favoriteMetadata: .init(name: name.isEmpty ? nil : name, shortcut: edit.shortcut, rank: old.favoriteMetadata?.rank ?? old.order), image: old.image, sourceBundleIdentifier: old.sourceBundleIdentifier, files: old.files)
        }
    }

    @discardableResult
    public func moveFavorite(id: UUID, offset: Int) async throws -> HistorySnapshot {
        guard offset == -1 || offset == 1 else { throw HistoryError.invalidFavoriteOrder }
        return try await repository.update { current in
            guard let index = current.favorites.firstIndex(where: { $0.id == id }) else { throw HistoryError.missingClip }
            let destination = index + offset
            guard current.favorites.indices.contains(destination) else { throw HistoryError.invalidFavoriteOrder }
            current.favorites.swapAt(index, destination)
            Self.rankFavorites(&current)
        }
    }

    private func assetsForExport(collection: CollectionKind, capacity: Int, enabled: Bool) async throws -> [String: Data] {
        guard enabled, let images = repository as? any ImageAssetRepository else { return [:] }
        let snapshot = try await repository.snapshot()
        let clips = collection == .recent ? snapshot.recent : snapshot.favorites
        let possible = Array(clips.suffix(max(0, clips.count - capacity + 1)))
        let assets = try await images.exportAssets(for: .init(recent: possible, favorites: []))
        return Dictionary(uniqueKeysWithValues: assets.map { ($0.hash, $0.png) })
    }
    private static func rankFavorites(_ snapshot: inout HistorySnapshot) {
        snapshot.favorites = snapshot.favorites.enumerated().map { index, clip in
            var metadata = clip.favoriteMetadata ?? FavoriteMetadata(rank: index)
            metadata.rank = index
            return clip.withFavoriteMetadata(metadata).withOrder(index)
        }
    }

    @discardableResult
    public func clearRecents() async throws -> HistorySnapshot {
        try await repository.apply(.clear(.recent))
    }

    @discardableResult
    public func delete(id: UUID) async throws -> HistorySnapshot {
        try await repository.apply(.delete(id))
    }

    @discardableResult
    public func moveToTop(id: UUID) async throws -> HistorySnapshot {
        try await repository.apply(.moveToTop(id))
    }

    @discardableResult
    public func mergeAll() async throws -> Clip? {
        let mergedID = UUID()
        let snapshot = try await repository.update { current in
            guard let newest = current.recent.first(where: { $0.contentKind == .text }) else { return }
            let merged = Clip(id: mergedID, text: current.recent.filter { $0.contentKind == .text }.reversed().map(\.text).joined(separator: "\n"), pasteboardType: newest.pasteboardType, sourceAppName: nil, sourceBundleURL: nil, capturedAt: Date(), collection: .recent, order: 0)
            current.recent = [merged] + current.recent.filter { $0.contentKind != .text }
        }
        return snapshot.recent.first { $0.id == mergedID }
    }
}

private extension Clip {
    var isUniversalControlSource: Bool {
        sourceAppName == "Universal Control" || sourceBundleURL?.contains("/UniversalControl.app/") == true
    }
}
