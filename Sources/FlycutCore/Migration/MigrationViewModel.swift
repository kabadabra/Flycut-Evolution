import Foundation

/// Content-free decisions shared by onboarding and manual import.
public struct MigrationViewModel: Sendable {
    public enum Action: String, Sendable { case choose, merge, replace }
    public enum Storage: String, Sendable { case choose, memory, onQuit, afterEachClip }
    public var sources: [LegacySource]
    public private(set) var selectedSource: LegacySource?
    public var action = Action.choose
    public var storage = Storage.choose
    public var confirmed = false
    public private(set) var importing = false
    private var destinationCount = 0
    private var memoryOnly = false
    private var importableCount = 0
    private var hasPreview = false
    public init(sources: [LegacySource]) { self.sources = sources }
    public mutating func select(_ source: LegacySource) {
        selectedSource = source; action = .choose; storage = .choose
        confirmed = false; hasPreview = false; importing = false
        if !sources.contains(source) { sources.append(source) }
    }
    public mutating func invalidatePreview() { hasPreview = false; confirmed = false }
    public mutating func acceptPreview(destinationCount: Int, inMemoryOnly: Bool, importableCount: Int) {
        self.destinationCount = destinationCount; memoryOnly = inMemoryOnly
        self.importableCount = importableCount; hasPreview = true; confirmed = false
    }
    public var canImport: Bool {
        selectedSource != nil && hasPreview && importableCount > 0 && !importing && confirmed &&
        (destinationCount == 0 || action != .choose) && (!memoryOnly || storage != .choose)
    }
    public var choice: MigrationChoice {
        switch action {
        case .merge: .merge(confirmed: confirmed)
        case .replace: .replace(confirmed: confirmed)
        case .choose: .importNew
        }
    }
    public var persistentSaveMode: SaveMode? {
        switch storage { case .onQuit: .onQuit; case .afterEachClip: .afterEachClip; default: nil }
    }
    public mutating func beginImport() -> Bool {
        guard canImport else { return false }; importing = true; return true
    }
    public mutating func failed() { importing = false; confirmed = false }
    public mutating func cancel() { self = Self(sources: sources) }
    public static func shouldOfferOnboarding(bundleIdentifier: String?, hasMarker: Bool) -> Bool {
        bundleIdentifier == "com.edynamics.flycut" && !hasMarker
    }
}
