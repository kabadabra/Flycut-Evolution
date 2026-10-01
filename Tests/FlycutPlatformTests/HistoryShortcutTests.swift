import AppKit
import Carbon
import XCTest
import FlycutCore
@testable import FlycutPlatform

@MainActor final class HistoryShortcutTests: XCTestCase {
    func testIndependentIdentifiersCannotHandleEachOthersEvents() {
        let paste = CarbonHotkeyClient(identifier: 1), history = CarbonHotkeyClient(identifier: 2)
        XCTAssertTrue(paste.ownsEvent(signature: 0x464C5943, id: 1))
        XCTAssertFalse(paste.ownsEvent(signature: 0x464C5943, id: 2))
        XCTAssertTrue(history.ownsEvent(signature: 0x464C5943, id: 2))
        XCTAssertFalse(history.ownsEvent(signature: 0x464C5943, id: 1))
        XCTAssertFalse(history.ownsEvent(signature: 123, id: 2))
    }
    func testFailedChangeRestoresCurrentShortcut() throws {
        let client = RejectingShortcutClient()
        let service = HotkeyService(client: client)
        let original = FlycutSettings().historyHotkey
        try service.register(original)
        XCTAssertThrowsError(try service.register(.init(keyCode: 0, modifierFlags: original.modifierFlags)))
        XCTAssertEqual(client.active, 9)
        XCTAssertEqual(service.currentShortcut, original)
    }
    func testSeparateShortcutsPersistWithoutChangingPlainPaste() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        var settings = store.load()
        let plain = settings.hotkey
        settings.historyHotkey = .init(keyCode: 8, modifierFlags: 1_572_864)
        store.save(settings)
        XCTAssertEqual(store.load().historyHotkey.keyCode, 8)
        XCTAssertEqual(store.load().hotkey, plain)
    }
}
@MainActor private final class RejectingShortcutClient: HotkeyClient {
    var active: UInt32?
    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) -> Int32 {
        if keyCode == 0 { return Int32(eventHotKeyExistsErr) }
        active = keyCode; return 0
    }
    func unregister() { active = nil }
}
