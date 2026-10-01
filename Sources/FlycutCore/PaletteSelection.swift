import Foundation

public struct PaletteSelection: Sendable {
    public var query = "" { didSet { searchClips = nil; if query.isEmpty { reconcile() } } }
    public var collection = CollectionKind.recent { didSet { searchClips = nil; if query.isEmpty { reconcile() } } }
    public var wraparound = false
    public private(set) var selectedID: UUID?
    public private(set) var snapshotRevision = UUID()
    private var snapshot = HistorySnapshot(recent: [], favorites: [])
    public init() {}
    private var searchClips: [Clip]?
    public var allClips: [Clip] { snapshot.favorites + snapshot.recent }
    public var filteredSourceClips: [Clip] { collection == .favorite ? snapshot.favorites : allClips }
    public var clips: [Clip] {
        if !query.isEmpty { return searchClips ?? [] }
        return collection == .favorite ? snapshot.favorites : Array(snapshot.favorites.prefix(5)) + snapshot.recent
    }
    public func clip(id: UUID) -> Clip? { allClips.first { $0.id == id } }
    public mutating func setSearchResults(_ clips: [Clip]) { searchClips = clips; reconcile() }
    public var selected: Clip? { clips.first { $0.id == selectedID } }
    public mutating func update(_ snapshot: HistorySnapshot) { self.snapshot = snapshot; snapshotRevision = UUID(); searchClips = nil; if query.isEmpty { reconcile() } }
    public mutating func select(_ id: UUID?) { selectedID = id; reconcile() }
    public mutating func move(_ distance: Int) {
        let list = clips
        guard !list.isEmpty else { selectedID = nil; return }
        let index = (list.firstIndex { $0.id == selectedID } ?? 0) + distance
        let next = wraparound ? ((index % list.count) + list.count) % list.count : min(max(index, 0), list.count - 1)
        selectedID = list[next].id
    }
    public mutating func home() { selectedID = clips.first?.id }
    public mutating func end() { selectedID = clips.last?.id }
    public mutating func selectDigit(_ digit: Int) {
        let index = digit == 0 ? 9 : digit - 1
        if clips.indices.contains(index) { selectedID = clips[index].id }
    }
    private mutating func reconcile() {
        if !clips.contains(where: { $0.id == selectedID }) { selectedID = clips.first?.id }
    }
}

public enum PaletteCommand: Equatable, Sendable {
    case activateID(UUID)
    case activate, activatePlain, dismiss, favorite, switchCollection, exportSelected, exportAll, delete, next, previous, digit(Int), copyToTop(UUID)
    public static func resolve(keyCode: UInt16, key: String, editingSearch: Bool) -> Self? {
        if keyCode == 53 { return .dismiss }
        if keyCode == 36 || keyCode == 76 { return .activate }
        return resolve(key: key, editingSearch: editingSearch)
    }
    public static func resolve(key: String, editingSearch: Bool) -> Self? {
        if key == "\r" { return .activate }
        if key == "\u{1b}" { return .dismiss }
        guard !editingSearch else { return nil }
        switch key {
        case "j": return .next
        case "k": return .previous
        case "f": return .favorite
        case "F": return .switchCollection
        case "s": return .exportSelected
        case "S": return .exportAll
        case "\u{7f}": return .delete
        default: return key.count == 1 ? Int(key).map(Self.digit) : nil
        }
    }
}
