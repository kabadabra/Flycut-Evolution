import AppKit
import XCTest
import FlycutCore
@testable import FlycutMac

@MainActor final class PaletteShortcutTests: XCTestCase {
    func testVisibleAndHiddenFavoriteActivationUseDifferentBindings() {
        let model = PaletteModel()
        let favorite = Clip(id: UUID(), text: "favorite", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil,
                            capturedAt: nil, collection: .favorite, order: 0, favoriteMetadata: .init(shortcut: 1, rank: 0))
        let recent = Clip(id: UUID(), text: "recent", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil,
                          capturedAt: nil, collection: .recent, order: 0)
        model.selection.update(.init(recent: [recent], favorites: [favorite]))
        model.selection.query = "recent"
        model.selection.setSearchResults([recent])
        var actions: [PaletteCommand] = []; model.perform = { actions.append($0) }
        model.activateVisibleNumber(1)
        model.activateFavoriteSlot(1)
        XCTAssertEqual(actions, [.activateID(recent.id), .activateID(favorite.id)])
        XCTAssertEqual(model.selection.query, "recent")
        XCTAssertNil(PaletteKeyboard.modifiedDigit(key: "1", modifiers: []))
        XCTAssertEqual(PaletteKeyboard.modifiedDigit(key: "1", modifiers: .command), .visible(1))
        XCTAssertEqual(PaletteKeyboard.modifiedDigit(key: "1", modifiers: [.command,.option]), .favorite(1))
    }
    func testConflictingOrMissingFavoriteShortcutDoesNotPaste() {
        let model = PaletteModel()
        let favorites = (0..<2).map { Clip(id: UUID(), text: "text", pasteboardType: "text", sourceAppName: nil,
            sourceBundleURL: nil, capturedAt: nil, collection: .favorite, order: $0, favoriteMetadata: .init(shortcut: 1, rank: $0)) }
        model.selection.update(.init(recent: [], favorites: favorites))
        var actions: [PaletteCommand] = []; model.perform = { actions.append($0) }
        model.activateFavoriteSlot(1); model.activateFavoriteSlot(2); model.activateVisibleNumber(9)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertNotNil(model.message)
    }
}
