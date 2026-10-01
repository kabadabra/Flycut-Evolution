import XCTest
import Sparkle
@testable import FlycutPlatform
@MainActor final class UpdateServiceTests: XCTestCase {
    func testDriverRegistersPermissionOptOutAndBuildOrdering() {
        let driver = SparkleUpdateDriver()
        XCTAssertTrue(driver.responds(to: NSSelectorFromString("updaterShouldPromptForPermissionToCheckForUpdates:")))
        let comparator = SUStandardVersionComparator()
        XCTAssertEqual(comparator.compareVersion("10003", toVersion: "1.0.2"), .orderedDescending)
        XCTAssertEqual(comparator.compareVersion("10003", toVersion: "10002"), .orderedDescending)
    }
    func testChecksOffBeforeStartAndManualCheckRequiresConfiguration() {
        var calls: [String] = []
        let client = UpdateClient(start: { calls.append("start") }, setAutomaticChecks: { calls.append("auto:\($0)") }, check: { calls.append("check") }, canCheck: { true })
        let updater = UpdateService(client: client, configured: true)
        updater.configure(automaticChecks: false); updater.start(); updater.checkForUpdates()
        XCTAssertEqual(calls, ["auto:false", "start", "check"])
        let unconfigured = UpdateService(client: client, configured: false)
        unconfigured.checkForUpdates()
        XCTAssertEqual(calls.count, 3)
        XCTAssertNotNil(unconfigured.message)
    }
    func testErrorCannotBeUpToDateAndConsentPersists() {
        var enabled = false
        let client = UpdateClient(start: {}, setAutomaticChecks: { enabled = $0 }, check: {}, canCheck: { true })
        let updater = UpdateService(client: client, configured: true)
        updater.configure(automaticChecks: true)
        XCTAssertTrue(enabled)
        updater.reportFailure("Feed unavailable")
        XCTAssertEqual(updater.message, "Feed unavailable")
    }
}
