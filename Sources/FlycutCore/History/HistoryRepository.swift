import Foundation

public struct MigrationMarker: Codable, Equatable, Sendable {
    public let sourceIdentity: String
    public let importedAt: Date
    public let importedSourceIdentities: [String]?

    public init(sourceIdentity: String, importedAt: Date, importedSourceIdentities: [String]? = nil) {
        self.sourceIdentity = sourceIdentity
        self.importedAt = importedAt
        self.importedSourceIdentities = importedSourceIdentities
    }
}

public struct HistorySnapshot: Codable, Equatable, Sendable {
    public var recent: [Clip]
    public var favorites: [Clip]
    public var migration: MigrationMarker?

    public init(recent: [Clip], favorites: [Clip], migration: MigrationMarker? = nil) {
        self.recent = recent
        self.favorites = favorites
        self.migration = migration
    }
}

public indirect enum HistoryChange: Sendable {
    case insert(Clip)
    case delete(UUID)
    case moveToTop(UUID)
    case clear(CollectionKind)
    case batch([HistoryChange])
}

public protocol HistoryRepository: Sendable {
    func snapshot() async throws -> HistorySnapshot
    func apply(_ change: HistoryChange) async throws -> HistorySnapshot
    /// Runs the synchronous mutation inside the same transaction as its read and write.
    /// Implementations must serialize it with apply and replaceAll, including migration writes.
    func update(_ body: @Sendable (inout HistorySnapshot) throws -> Void) async throws -> HistorySnapshot
    func replaceAll(_ snapshot: HistorySnapshot) async throws
}

public enum HistoryError: Error, Equatable, Sendable {
    case duplicateID
    case missingClip
    case invalidCollection
    case unsupportedSchema(Int)
    case staleSnapshot
    case database(String)
}
