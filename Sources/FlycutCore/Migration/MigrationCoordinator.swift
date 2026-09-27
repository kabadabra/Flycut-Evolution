import Foundation
import Darwin
import CryptoKit

public actor MigrationCoordinator {
    private let destination: any HistoryRepository
    private let backupDirectory: URL
    public private(set) var activeRepository: any HistoryRepository
    private var memoryRepository: (any HistoryRepository)?
    private var importing = false
    private var memoryBackups: [String: (Data, HistorySnapshot)] = [:]

    public init(destination: any HistoryRepository, backupDirectory: URL, memoryDestination: (any HistoryRepository)? = nil) {
        self.memoryRepository = memoryDestination
        self.destination = destination
        self.activeRepository = destination
        self.backupDirectory = backupDirectory
    }

    public func preview(source: LegacySource, destination: (any HistoryRepository)? = nil, choice: MigrationChoice = .importNew, persistentSaveMode: SaveMode? = nil) async throws -> MigrationReport {
        let data = try Data(contentsOf: source.url)
        var parsed = try LegacyStoreParser.parse(data: data)
        if let persistentSaveMode, persistentSaveMode != .never { parsed.settings.saveMode = persistentSaveMode }
        let history: HistorySnapshot
        if let destination {
            history = try await destination.snapshot()
        } else if parsed.settings.saveMode == .never {
            history = try await memoryRepository?.snapshot() ?? HistorySnapshot(recent: [], favorites: [])
        } else {
            history = try await self.destination.snapshot()
        }
        var report = Self.report(source: source, parsed: parsed, destination: history)
        report.sourceFingerprint = Self.fingerprint(data)
        report.destinationFingerprint = try Self.fingerprint(history)
        report.alreadyImported = Self.contains(history.migration, source: source)
        if case .merge = choice, !report.alreadyImported {
            report.settings.recentCapacity = max(report.settings.recentCapacity, history.recent.count + report.recentCount)
            report.settings.favoriteCapacity = max(report.settings.favoriteCapacity, history.favorites.count + report.favoriteCount)
        }
        if report.inMemoryOnly {
            report.warnings.append("Save-never: import and backups stay in memory unless you choose a persistent save mode.")
        }
        return report
    }

    /// A persistent mode is an explicit user opt-in when the legacy save mode is never.
    /// Adopt activeRepository and report.settingsForAdoption(preserving: currentSettings)
    /// together. No-op imports retain current settings and only raise insufficient capacities.
    public func `import`(source: LegacySource, choice: MigrationChoice, persistentSaveMode: SaveMode? = nil, expectedSourceFingerprint: String? = nil, expectedDestinationFingerprint: String? = nil) async throws -> MigrationReport {
        guard !importing else { throw MigrationError.importInProgress }
        importing = true
        defer { importing = false }
        let data = try Data(contentsOf: source.url)
        if let expectedSourceFingerprint, expectedSourceFingerprint != Self.fingerprint(data) { throw MigrationError.previewChanged }
        var parsed = try LegacyStoreParser.parse(data: data)
        if let persistentSaveMode, persistentSaveMode != .never { parsed.settings.saveMode = persistentSaveMode }
        guard !parsed.history.recent.isEmpty || !parsed.history.favorites.isEmpty else { throw MigrationError.nothingImportable }
        let memoryOnly = parsed.settings.saveMode == .never
        let target: any HistoryRepository
        if memoryOnly {
            if memoryRepository == nil { memoryRepository = try SQLiteHistoryRepository(inMemory: ()) }
            target = memoryRepository!
        } else { target = destination }
        let before = try await target.snapshot()
        if let expectedDestinationFingerprint, expectedDestinationFingerprint != (try Self.fingerprint(before)) { throw MigrationError.previewChanged }
        var report = Self.report(source: source, parsed: parsed, destination: before)
        report.sourceFingerprint = Self.fingerprint(data)
        report.destinationFingerprint = try Self.fingerprint(before)
        if Self.contains(before.migration, source: source) {
            report.alreadyImported = true
            activeRepository = target
            return report
        }
        try Self.validate(choice, destination: before)
        let backupID = UUID().uuidString
        let sourceBackup = backupDirectory.appendingPathComponent("\(backupID)-source.plist")
        let destinationBackup = backupDirectory.appendingPathComponent("\(backupID)-destination.json")
        if !memoryOnly { try Self.privateWrite(data, to: sourceBackup) }
        let imported = parsed.history
        let timestamp = Date()
        let result = try await target.update { current in
            if let expectedDestinationFingerprint, expectedDestinationFingerprint != (try Self.fingerprint(current)) { throw MigrationError.previewChanged }
            if Self.contains(current.migration, source: source) { return }
            try Self.validate(choice, destination: current)
            if !memoryOnly && (!current.recent.isEmpty || !current.favorites.isEmpty) {
                try Self.privateWrite(JSONEncoder().encode(current), to: destinationBackup)
            }
            let identities = Set((current.migration?.importedSourceIdentities ?? []) + [current.migration?.sourceIdentity, source.identity].compactMap { $0 })
            switch choice {
            case .merge: current.recent += imported.recent; current.favorites += imported.favorites
            case .importNew, .replace: current.recent = imported.recent; current.favorites = imported.favorites
            }
            current.migration = MigrationMarker(sourceIdentity: source.identity, importedAt: timestamp, importedSourceIdentities: identities.sorted())
        }
        report.importedCount = imported.recent.count + imported.favorites.count
        report.settings.recentCapacity = max(report.settings.recentCapacity, result.recent.count)
        report.settings.favoriteCapacity = max(report.settings.favoriteCapacity, result.favorites.count)
        if memoryOnly {
            memoryBackups[source.identity] = (data, before)
            report.warnings.append("Save-never: history, migration marker and backups remain in memory; no new clipboard files were written.")
        } else {
            report.sourceBackup = sourceBackup
            if FileManager.default.fileExists(atPath: destinationBackup.path) { report.destinationBackup = destinationBackup }
        }
        activeRepository = target
        return report
    }

    private static func fingerprint(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func fingerprint(_ snapshot: HistorySnapshot) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return fingerprint(try encoder.encode(snapshot))
    }

    private static func contains(_ marker: MigrationMarker?, source: LegacySource) -> Bool {
        guard let marker else { return false }
        return ([marker.sourceIdentity] + (marker.importedSourceIdentities ?? [])).contains { source.matchesStoredIdentity($0) }
    }

    private static func validate(_ choice: MigrationChoice, destination: HistorySnapshot) throws {
        guard !destination.recent.isEmpty || !destination.favorites.isEmpty else { return }
        switch choice {
        case .merge(confirmed: true), .replace(confirmed: true): return
        default: throw MigrationError.confirmationRequired
        }
    }

    private static func report(source: LegacySource, parsed: LegacySnapshot, destination: HistorySnapshot) -> MigrationReport {
        var settings = parsed.settings
        settings.recentCapacity = max(settings.recentCapacity, destination.recent.count)
        settings.favoriteCapacity = max(settings.favoriteCapacity, destination.favorites.count)
        return MigrationReport(source: source, recentCount: parsed.history.recent.count, favoriteCount: parsed.history.favorites.count,
                        destinationCount: destination.recent.count + destination.favorites.count,
                        destinationRecentCount: destination.recent.count, destinationFavoriteCount: destination.favorites.count, settings: settings,
                        skipped: parsed.skipped, warnings: parsed.warnings, inMemoryOnly: parsed.settings.saveMode == .never)
    }

    /// O_EXCL and 0600 protect clipboard bytes from the instant the file is created.
    private static func privateWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HistoryError.database("Unable to create private migration backup") }
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
}
