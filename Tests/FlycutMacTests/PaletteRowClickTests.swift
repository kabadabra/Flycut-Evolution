import XCTest
import AppKit
import FlycutCore
@testable import FlycutMac

@MainActor final class PaletteRowClickTests: XCTestCase {
    func testFirstMouseDownPastesImmediatelyAndSecondDoesNotPasteAgain() {
        let model = PaletteModel()
        let clips = (0..<2).map { index in
            Clip(id: UUID(), text: "Synthetic \(index)", pasteboardType: "public.utf8-plain-text",
                 sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: index)
        }
        model.selection.update(.init(recent: clips, favorites: []))
        var actions: [PaletteCommand] = []
        model.perform = { actions.append($0) }
        let view = ImmediateRowClickView { model.handleRowClick(clips[1].id, clickCount: $0) }

        view.mouseDown(with: mouseEvent(clickCount: 1))
        XCTAssertEqual(model.selection.selectedID, clips[1].id)
        XCTAssertEqual(actions, [.activate])

        view.mouseDown(with: mouseEvent(clickCount: 2))
        XCTAssertEqual(model.selection.selectedID, clips[1].id)
        XCTAssertEqual(actions, [.activate])
    }

    func testPlainActionSelectsItsOwnRowWithoutFormattedActivation() {
        let model = PaletteModel()
        let clips = (0..<2).map { index in
            Clip(id: UUID(), text: "Synthetic \(index)", pasteboardType: "public.utf8-plain-text",
                 sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent,
                 order: index, formattedRTF: Data("{\\rtf1\\ansi Styled}".utf8))
        }
        model.selection.update(.init(recent: clips, favorites: []))
        var actions: [PaletteCommand] = []
        model.perform = { actions.append($0) }
        model.handlePlainRowClick(clips[1].id)
        XCTAssertEqual(model.selection.selectedID, clips[1].id)
        XCTAssertEqual(actions, [.activatePlain])
    }

    func testImmediateRowSurfaceReportsHoverWithoutClicking() {
        var hovered: [Bool] = []
        var clicks = 0
        let view = ImmediateRowClickView(onClick: { _ in clicks += 1 }, onHover: { hovered.append($0) })
        view.mouseEntered(with: mouseEvent(clickCount: 0))
        view.mouseExited(with: mouseEvent(clickCount: 0))
        XCTAssertEqual(hovered, [true, false])
        XCTAssertEqual(clicks, 0)
    }

    func testRowHoverHighlightsWithoutChangingKeyboardSelection() {
        let model = PaletteModel()
        let first = Clip(id: UUID(), text: "Synthetic one", pasteboardType: "public.utf8-plain-text", sourceAppName: nil,
                         sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let second = Clip(id: UUID(), text: "Synthetic two", pasteboardType: "public.utf8-plain-text", sourceAppName: nil,
                          sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 1)
        model.selection.update(.init(recent: [first, second], favorites: []))
        model.selection.select(first.id)
        model.rowHovered(second.id, inside: true)
        XCTAssertEqual(model.hoveredClipID, second.id)
        XCTAssertEqual(model.selection.selectedID, first.id)
        model.rowHovered(second.id, inside: false)
        XCTAssertNil(model.hoveredClipID)
        model.rowHovered(second.id, inside: true)
        model.clearHover()
        XCTAssertNil(model.hoveredClipID)
    }

    func testPreviewUsesAppControlledDismissalInsteadOfTransientClickDismissal() {
        let presenter = HoverPreviewPresenter()
        XCTAssertEqual(presenter.popover.behavior, .applicationDefined)
    }

    private func mouseEvent(clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1,
                           clickCount: clickCount, pressure: 1)!
    }
}
