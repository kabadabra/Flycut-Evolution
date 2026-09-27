import XCTest
@testable import FlycutCore

final class PaletteModelTests: XCTestCase {
    private func clip(_ text: String, _ collection: CollectionKind = .recent) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: collection, order: 0)
    }
    func testFilteringResetsMissingSelectionAndKeepsStableIdentity() {
        let a = clip("Alpha"), b = clip("Beta"), f = clip("Favorite", .favorite)
        var state = PaletteSelection()
        state.update(HistorySnapshot(recent: [a,b], favorites: [f]))
        state.select(b.id)
        state.query = "ALP"
        XCTAssertEqual(state.clips.map(\.id), [a.id])
        XCTAssertEqual(state.selectedID, a.id)
        state.collection = .favorite
        XCTAssertNil(state.selectedID)
        state.query = ""
        XCTAssertEqual(state.selectedID, f.id)
    }
    func testNavigationClampsWrapsAndHandlesEmptyResults() {
        let a = clip("A"), b = clip("B"), c = clip("C")
        var state = PaletteSelection()
        state.update(HistorySnapshot(recent: [a,b,c], favorites: []))
        state.move(-1); XCTAssertEqual(state.selectedID, a.id)
        state.wraparound = true
        state.move(-1); XCTAssertEqual(state.selectedID, c.id)
        state.move(1); XCTAssertEqual(state.selectedID, a.id)
        state.end(); XCTAssertEqual(state.selectedID, c.id)
        state.home(); XCTAssertEqual(state.selectedID, a.id)
        state.selectDigit(2); XCTAssertEqual(state.selectedID, b.id)
        state.selectDigit(9); XCTAssertEqual(state.selectedID, b.id)
        state.query = "missing"; state.move(1); XCTAssertNil(state.selectedID)
    }
    func testEscapeUsesHardwareCodeWhenCharactersAreEmpty() {
        XCTAssertEqual(PaletteCommand.resolve(keyCode: 53, key: "", editingSearch: true), .dismiss)
        XCTAssertEqual(PaletteCommand.resolve(keyCode: 76, key: "", editingSearch: false), .activate)
    }
    func testTypingDoesNotTriggerDestructiveOrLetterCommands() {
        XCTAssertNil(PaletteCommand.resolve(key: "f", editingSearch: true))
        XCTAssertNil(PaletteCommand.resolve(key: "\u{7f}", editingSearch: true))
        XCTAssertEqual(PaletteCommand.resolve(key: "F", editingSearch: false), .switchCollection)
        XCTAssertEqual(PaletteCommand.resolve(key: "f", editingSearch: false), .favorite)
        XCTAssertEqual(PaletteCommand.resolve(key: "S", editingSearch: false), .exportAll)
        XCTAssertEqual(PaletteCommand.resolve(key: "\r", editingSearch: true), .activate)
    }
}
