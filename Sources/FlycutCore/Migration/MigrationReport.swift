import Foundation

public struct LegacySource: Sendable, Equatable {
    public let url: URL
    /// The same file selected through discovery, the picker, or a symlink has one identity.
    public let identity: String
    public let displayDomain: String?

    public init(url: URL) {
        self.url = url
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        self.identity = canonicalURL.path
        self.displayDomain = LegacySourceDiscovery.domains.first { domain in
            canonicalURL.path.hasSuffix("/Library/Preferences/\(domain).plist")
        }
    }

    /// Accept markers written by the earlier domain/path implementation as aliases.
    internal func matchesStoredIdentity(_ stored: String) -> Bool {
        if stored == identity || stored == displayDomain { return true }
        guard stored.hasPrefix("/") else { return false }
        return URL(fileURLWithPath: stored).resolvingSymlinksInPath().standardizedFileURL.path == identity
    }
}

public struct SkippedLegacyRecord: Sendable, Equatable {
    public let collection: CollectionKind
    public let index: Int
    public let reason: String
}

public struct LegacySnapshot: Sendable {
    public let history: HistorySnapshot
    public var settings: FlycutSettings
    public let skipped: [SkippedLegacyRecord]
    public let warnings: [String]
}

public struct MigrationReport: Sendable {
    public let source: LegacySource
    public let recentCount: Int
    public let favoriteCount: Int
    public let destinationCount: Int
    public let destinationRecentCount: Int
    public let destinationFavoriteCount: Int
    public var settings: FlycutSettings
    public let skipped: [SkippedLegacyRecord]
    public var warnings: [String]
    public var sourceFingerprint = ""
    public var destinationFingerprint = ""
    public var importedCount = 0
    public var alreadyImported = false
    public var inMemoryOnly: Bool
    public var sourceBackup: URL?
    public var destinationBackup: URL?

    /// Source settings are applied only when new data is imported. A no-op retains
    /// the user's current preferences while ensuring capacity fits retained history.
    public func settingsForAdoption(preserving current: FlycutSettings) -> FlycutSettings {
        guard alreadyImported else { return settings }
        var result = current
        result.recentCapacity = max(result.recentCapacity, destinationRecentCount)
        result.favoriteCapacity = max(result.favoriteCapacity, destinationFavoriteCount)
        return result
    }
}

public enum MigrationChoice: Sendable {
    case importNew
    case merge(confirmed: Bool)
    case replace(confirmed: Bool)
}

public enum MigrationError: Error, Equatable, Sendable {
    case previewChanged
    case absentStore
    case invalidPropertyList
    case nothingImportable
    case confirmationRequired
    case importInProgress
}

public struct LegacySourceDiscovery: Sendable {
    internal static let domains = ["com.edynamics.flycut", "com.kabadabra.flycut", "com.generalarcade.flycut"]
    public let sources: [LegacySource]
    public let inaccessibleSources: [LegacySource]
    public let offersFilePicker = true

    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LegacySource] {
        domains.map { domain in
            let path = domain == "com.generalarcade.flycut"
                ? "Library/Containers/\(domain)/Data/Library/Preferences/\(domain).plist"
                : "Library/Preferences/\(domain).plist"
            return LegacySource(url: home.appendingPathComponent(path))
        }
    }

    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        var sources: [LegacySource] = [], inaccessible: [LegacySource] = []
        for source in candidates(home: home) {
            do {
                _ = try FileHandle(forReadingFrom: source.url).close()
                sources.append(source)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            catch { inaccessible.append(source) }
        }
        return Self(sources: sources, inaccessibleSources: inaccessible)
    }
}
