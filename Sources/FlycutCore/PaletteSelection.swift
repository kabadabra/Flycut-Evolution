import Foundation

public struct PaletteSelection: Sendable {
    public var query = "" { didSet { reconcile() } }
    public var collection = CollectionKind.recent { didSet { reconcile() } }
    public var wraparound = false
    public private(set) var selectedID: UUID?
    private var snapshot = HistorySnapshot(recent: [], favorites: [])
    public init() {}
    public var clips: [Clip] {
        let list = collection == .recent ? snapshot.recent : snapshot.favorites
        return query.isEmpty ? list : list.filter { $0.text.localizedStandardContains(query) }
    }
    public var selected: Clip? { clips.first { $0.id == selectedID } }
    public mutating func update(_ snapshot: HistorySnapshot) { self.snapshot = snapshot; reconcile() }
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
