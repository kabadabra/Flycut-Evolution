import XCTest
import FlycutCore
@testable import FlycutMac
@MainActor final class SetupModelTests: XCTestCase {
    func testPermissionRefreshNeverPromptsAndSampleIsExplicit() {
        var trusted = false, prompts = 0, copies = 0
        let model = SetupModel(settings: FlycutSettings(), permission: .init(status: { trusted }, request: { prompts += 1; return trusted }, open: {}), copySample: { copies += 1 }, save: { _, _ in })
        model.refreshPermission(); XCTAssertEqual(prompts, 0); XCTAssertEqual(copies, 0)
        trusted = true; model.refreshPermission(); XCTAssertTrue(model.trusted)
        model.requestPermission(); XCTAssertEqual(prompts, 1)
        model.copySample(); XCTAssertEqual(copies, 1)
        XCTAssertNil(model.pasteSucceeded)
        model.confirmPaste(true); XCTAssertEqual(model.pasteSucceeded, true)
    }
    func testDismissAndReopenAreIndependentOfPalette() {
        var saved = SetupState()
        let model = SetupModel(settings: FlycutSettings(), save: { _, state in saved = state })
        model.dismiss(); XCTAssertTrue(saved.dismissed)
        model.next(); XCTAssertEqual(model.state.step, .shortcuts)
        model.finish(); XCTAssertTrue(saved.completed)
    }
}
