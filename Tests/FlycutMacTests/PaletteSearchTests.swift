import XCTest
import FlycutCore
@testable import FlycutMac

@MainActor final class PaletteSearchTests: XCTestCase {
    private func clip(_ text: String, favorite: Bool = false, rank: Int = 0) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil,
             collection: favorite ? .favorite : .recent, order: rank)
    }
    func testNewerSearchWinsAfterQuerySnapshotAndFilterChanges() async {
        let model = PaletteModel()
        let a = clip("Alpha"), b = clip("Beta"), f = clip("Beta favorite", favorite: true)
        model.searchProvider = { query, clips in
            try? await Task.sleep(for: .milliseconds(query == "Alpha" ? 400 : 5))
            return ClipSearch.search(query, in: clips)
        }
        model.updateSnapshot(.init(recent: [a,b], favorites: [f]))
        model.selection.query = "Alpha"
        try? await Task.sleep(for: .milliseconds(150))
        model.selection.query = "Beta"
        model.selection.collection = .favorite
        await model.searchTask?.value
        XCTAssertEqual(model.visibleClips.map(\.id), [f.id])
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(model.visibleClips.map(\.id), [f.id])
        model.updateSnapshot(.init(recent: [], favorites: []))
        await model.searchTask?.value
        XCTAssertTrue(model.visibleClips.isEmpty)
    }
    func testCompactFavoritesAreAdditionalToRecentPreview() async {
        let model = PaletteModel()
        var settings = FlycutSettings(); settings.menuPreviewCount = 2; model.apply(settings)
        let recents = (0..<4).map { clip("recent \($0)", rank: $0) }
        let favorites = (0..<8).map { clip("favorite \($0)", favorite: true, rank: $0) }
        model.updateSnapshot(.init(recent: recents, favorites: favorites))
        XCTAssertEqual(model.visibleClips.count, 7)
        model.selection.collection = .favorite
        XCTAssertEqual(model.visibleClips.count, 8)
        model.selection.collection = .recent; model.selection.query = "favorite"
        await model.searchTask?.value
        XCTAssertEqual(model.visibleClips.count, 8)
    }
    func testDismissalRejectsInFlightSearchAndPreservesSelectionWhenStillMatched() async {
        let model = PaletteModel()
        let a = clip("note Alpha"), b = clip("note Beta")
        model.updateSnapshot(.init(recent: [a,b], favorites: [])); model.selection.select(b.id)
        model.selection.query = "note"
        await model.searchTask?.value
        XCTAssertEqual(model.selection.selectedID, b.id)
        model.selection.query = "Alpha"; model.cancelPresentation()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(model.isSearching)
        model.updateSnapshot(.init(recent: [a,b], favorites: []))
        XCTAssertNil(model.searchTask, "Closed palettes must not restart a stale search after capture")
        model.preparePresentation()
        XCTAssertEqual(model.selection.query, "")
        XCTAssertEqual(model.visibleClips.map(\.id), [a.id,b.id])
    }
    func testFilteredReorderControlsUseFullManualOrder() async {
        let model = PaletteModel()
        let a = clip("first", favorite: true), b = clip("middle", favorite: true, rank: 1), c = clip("last", favorite: true, rank: 2)
        model.updateSnapshot(.init(recent: [], favorites: [a,b,c]))
        model.selection.collection = .favorite; model.selection.query = "middle"
        await model.searchTask?.value
        XCTAssertEqual(model.visibleClips.map(\.id), [b.id])
        XCTAssertTrue(model.canMoveFavorite(b.id, offset: -1)); XCTAssertTrue(model.canMoveFavorite(b.id, offset: 1))
        XCTAssertFalse(model.canMoveFavorite(a.id, offset: -1)); XCTAssertFalse(model.canMoveFavorite(c.id, offset: 1))
    }

}
