import XCTest
@testable import FlycutCore
final class SetupStateTests: XCTestCase {
    func testFreshStateAndCompletionPersistWithoutImplicitConsent() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.isEstablishedInstallation)
        let settings = store.load()
        XCTAssertFalse(settings.automaticUpdateChecks)
        XCTAssertFalse(settings.imageSyncEnabled)
        var state = store.loadSetup()
        XCTAssertFalse(state.handled)
        state.dismissed = true
        store.saveSetup(state)
        XCTAssertTrue(store.loadSetup().handled)
    }
}
