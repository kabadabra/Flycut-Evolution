import XCTest
import AppKit
import FlycutCore
@testable import FlycutMac

@MainActor final class PalettePreferencesTests: XCTestCase {
    func testPreviewLimitNeverHidesSearchOrKeyboardSelection() {
        let model = PaletteModel()
        var settings = FlycutSettings(); settings.menuPreviewCount = 2
        model.apply(settings)
        let clips = (0..<5).map { Clip(id: UUID(), text: "Synthetic \($0)", pasteboardType: "public.utf8-plain-text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: $0) }
        model.selection.update(.init(recent: clips, favorites: []))
        XCTAssertEqual(model.visibleClips.count, 2)
        model.selection.end()
        XCTAssertEqual(model.visibleClips.last?.id, clips.last?.id)
        model.selection.home()
        model.selection.query = "Synthetic 4"
        XCTAssertEqual(model.visibleClips.map(\.id), [clips[4].id])
        model.selection.query = ""
        model.showAll = true
        XCTAssertEqual(model.visibleClips.count, 5)
        XCTAssertEqual(model.selection.clips.count, 5)
    }
    func testRowActivationIgnoresLegacyCopyPreference() {
        let model = PaletteModel()
        let clip = Clip(id: UUID(), text: "Synthetic", pasteboardType: "public.utf8-plain-text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        model.selection.update(.init(recent: [clip], favorites: []))
        var actions: [PaletteCommand] = []; model.perform = { actions.append($0) }
        var settings = FlycutSettings(); settings.menuSelectionPastes = false
        model.apply(settings); model.activateSelection()
        XCTAssertEqual(actions, [.activate])
        settings.menuSelectionPastes = true
        model.apply(settings); model.activateSelection()
        XCTAssertEqual(actions, [.activate, .activate])
    }
    func testSuppressionKeepsFallbackAndPermissionLinkAndAlertOccursOnce() {
        let model = PaletteModel()
        var settings = FlycutSettings(); settings.suppressAccessibilityAlert = true
        model.apply(settings); model.reportAccessibilityDenied()
        XCTAssertFalse(model.showAccessibilityAlert)
        XCTAssertTrue(model.needsAccessibility); XCTAssertNotNil(model.message)
        settings.suppressAccessibilityAlert = false
        model.apply(settings); model.reportAccessibilityDenied()
        XCTAssertTrue(model.showAccessibilityAlert)
        model.showAccessibilityAlert = false
        model.reportAccessibilityDenied()
        XCTAssertFalse(model.showAccessibilityAlert)
        XCTAssertTrue(model.needsAccessibility)
    }
    func testPresentationBoundsRespectUsableMinimumAndSmallScreens() {
        XCTAssertEqual(PalettePresentation.size(FlycutSettings(), available: NSSize(width: 1400, height: 900)), NSSize(width: 460, height: 700))
        var settings = FlycutSettings(); settings.bezelWidth = 200; settings.bezelHeight = 160
        XCTAssertEqual(PalettePresentation.size(settings, available: NSSize(width: 1400, height: 900)), NSSize(width: 460, height: 400))
        settings.bezelWidth = 1600; settings.bezelHeight = 1200
        XCTAssertEqual(PalettePresentation.size(settings, available: NSSize(width: 800, height: 600)), NSSize(width: 768, height: 568))
        XCTAssertEqual(PalettePresentation.size(settings, available: NSSize(width: 400, height: 300)), NSSize(width: 368, height: 268))
    }
    func testResizingNearScreenEdgeKeepsEntirePanelVisible() {
        let screen = NSRect(x: 1000, y: 100, width: 1000, height: 700)
        let resized = NSRect(x: 1850, y: 650, width: 650, height: 500)
        XCTAssertEqual(PalettePresentation.constrain(resized, to: screen), NSRect(x: 1334, y: 284, width: 650, height: 500))
    }
    func testAnimationRequiresOptInAndRespectsReduceMotion() {
        var settings = FlycutSettings()
        XCTAssertFalse(PalettePresentation.animates(settings, reduceMotion: false))
        settings.popUpAnimation = true
        XCTAssertTrue(PalettePresentation.animates(settings, reduceMotion: false))
        XCTAssertFalse(PalettePresentation.animates(settings, reduceMotion: true))
    }
    func testMenuBarChoicesUseNativeShapesWithExplicitCompactRendering() {
        let button = NSButton()
        let choices: [(Int, NSSize, NSImage.SymbolConfiguration)] = [
            (0, NSSize(width: 19, height: 20), .init(pointSize: 13, weight: .semibold)),
            (1, NSSize(width: 18, height: 15), .init(pointSize: 11, weight: .bold)),
            (2, NSSize(width: 17, height: 14), .init(pointSize: 12, weight: .semibold))
        ]
        for (choice, maximumSize, configuration) in choices {
            MenuBarIcon.configure(button, choice: choice)
            XCTAssertEqual(button.symbolConfiguration, configuration)
            XCTAssertEqual(button.imageScaling, .scaleNone)
            XCTAssertEqual(button.image?.symbolConfiguration, configuration)
            // SF Symbol geometry varies slightly with the macOS symbol catalog.
            let size = button.image?.size ?? .zero
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.width, maximumSize.width)
            XCTAssertLessThanOrEqual(size.height, maximumSize.height)
            XCTAssertTrue(button.image?.isTemplate == true)
        }
    }
}
