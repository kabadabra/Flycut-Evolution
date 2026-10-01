import XCTest
import FlycutCore
@testable import FlycutMac

@MainActor final class FavoriteEditorTests: XCTestCase {
    private func favorite() -> Clip {
        Clip(id: UUID(), text: "saved", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil,
             capturedAt: nil, collection: .favorite, order: 0, favoriteMetadata: .init(name: "Name", shortcut: 1, rank: 0))
    }
    func testCancelDoesNotSaveAndFailedSaveKeepsDraftOpen() async {
        let model = PaletteModel(); let clip = favorite()
        model.updateSnapshot(.init(recent: [], favorites: [clip]))
        var calls = 0
        model.saveFavorite = { _,_ in calls += 1; throw HistoryError.database("Failed") }
        model.beginFavoriteEdit(clip.id); model.favoriteEdit.text = "changed"; model.cancelFavoriteEdit()
        XCTAssertEqual(calls, 0)
        model.beginFavoriteEdit(clip.id); model.favoriteEdit.text = "changed"
        await model.saveFavoriteEdit()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.editedFavoriteID, clip.id)
        XCTAssertEqual(model.favoriteEdit.text, "changed")
        XCTAssertNotNil(model.favoriteError)
        XCTAssertEqual(model.selection.clip(id: clip.id)?.text, "saved")
    }
    func testDeletedFavoriteCannotBeSavedAndSuccessClosesEditor() async {
        let model = PaletteModel(); let clip = favorite()
        model.updateSnapshot(.init(recent: [], favorites: [clip])); model.beginFavoriteEdit(clip.id)
        model.updateSnapshot(.init(recent: [], favorites: []))
        var calls = 0; model.saveFavorite = { _,_ in calls += 1 }
        await model.saveFavoriteEdit(); XCTAssertEqual(calls, 0); XCTAssertNotNil(model.favoriteError)
        model.updateSnapshot(.init(recent: [], favorites: [clip])); model.beginFavoriteEdit(clip.id)
        await model.saveFavoriteEdit(); XCTAssertEqual(calls, 1); XCTAssertNil(model.editedFavoriteID)
    }
}
