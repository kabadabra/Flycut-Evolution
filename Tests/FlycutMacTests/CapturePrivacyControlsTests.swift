import XCTest
import FlycutCore
@testable import FlycutMac
import FlycutPlatform
final class CapturePrivacyControlsTests: XCTestCase {
    func testMenuDurationsAndPendingLabel() {
        XCTAssertEqual(CapturePrivacyControls.pauseDurations, [300, 900, 3600])
        var state = CaptureSessionState()
        XCTAssertEqual(CapturePrivacyControls.label(state), nil)
        state.ignoreNextCopy()
        XCTAssertEqual(CapturePrivacyControls.label(state), "Next copy will be ignored")
        state.setPause(.until(Date(timeIntervalSince1970: 300)))
        XCTAssertTrue(CapturePrivacyControls.label(state)?.contains("until") == true)
    }
    @MainActor func testInvalidApplicationPickerRejectsWithoutReturningEntry() {
        XCTAssertThrowsError(try ExcludedApplicationPicker.application(at: URL(fileURLWithPath: "/tmp/not-an-application.txt")))
    }
    func testExclusionRoundTripAndDeduplication() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var settings = FlycutSettings()
        settings.excludedApplications = [.init(bundleIdentifier: "example.private", displayName: "Private"), .init(bundleIdentifier: "example.private", displayName: "Again"), .init(bundleIdentifier: "", displayName: "Invalid")]
        let store = SettingsStore(defaults: defaults)
        store.save(settings)
        XCTAssertEqual(store.load().excludedApplications.count, 1)
        XCTAssertEqual(store.load().excludedApplications.first?.displayName, "Private")
    }
}
