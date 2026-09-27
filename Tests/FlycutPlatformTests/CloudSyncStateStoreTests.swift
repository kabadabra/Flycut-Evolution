import Foundation
import XCTest
import FlycutCore
@testable import FlycutPlatform

final class CloudSyncStateStoreTests: XCTestCase {
    func testPrivateStatePersistsAcrossRestartWithoutWorldReadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sync-state.json")
        let store = CloudSyncStateStore(url: url)
        let initial = CloudSyncDiskState(accountID: "synthetic-account", ledger: CloudSyncLedger(deviceID: "Mac-A"))
        try store.save(initial)
        XCTAssertEqual(try store.load()?.accountID, initial.accountID)
        XCTAssertEqual(try store.load()?.ledger, initial.ledger)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        var changed = initial
        changed.lastSuccess = Date(timeIntervalSince1970: 123)
        try store.save(changed)
        XCTAssertEqual(try store.load()?.lastSuccess, changed.lastSuccess)
    }

    func testCorruptStateIsReportedAndNeverSilentlyReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sync-state.json")
        let store = CloudSyncStateStore(url: url)
        XCTAssertNil(try store.load())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: url), Data("not JSON".utf8))
    }
}
