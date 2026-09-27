import CloudKit
import Foundation
import XCTest
import FlycutCore
@testable import FlycutPlatform

final class CloudSyncControllerTests: XCTestCase {
    private func clip() -> Clip {
        Clip(id: UUID(), text: "Synthetic cloud check", pasteboardType: "public.utf8-plain-text",
             sourceAppName: "Test", sourceBundleURL: nil, capturedAt: Date(), collection: .recent, order: 0)
    }

    func testExplicitStartBindsCurrentAccountAndRestoresPendingState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSyncStateStore(url: directory.appendingPathComponent("state.json"))
        let original = HistorySnapshot(recent: [clip()], favorites: [])
        let first = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        let prepared = try await first.prepare(original, reauthorize: true)
        XCTAssertEqual(prepared.recent.map(\.id), original.recent.map(\.id))
        XCTAssertEqual(try store.load()?.accountID, "account-A")
        XCTAssertEqual(try store.load()?.ledger.pendingEntries.count, 1)
        let second = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        let resumed = try await second.prepare(original, reauthorize: false)
        XCTAssertEqual(resumed.recent.map(\.id), original.recent.map(\.id))
    }

    func testAccountSwitchRequiresNewExplicitOptInAndPreservesLocalHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSyncStateStore(url: directory.appendingPathComponent("state.json"))
        let original = HistorySnapshot(recent: [clip()], favorites: [])
        let first = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        _ = try await first.prepare(original, reauthorize: true)
        let second = CloudSyncController(store: store, accountIdentity: { "account-B" }, onRemote: { _ in }, onStatus: { _ in })
        do { _ = try await second.prepare(original, reauthorize: false); XCTFail("Account switch must stop") }
        catch { XCTAssertEqual(error as? CloudSyncError, .accountChanged) }
        XCTAssertEqual(try store.load()?.accountID, "account-A")
        let authorized = try await second.prepare(original, reauthorize: true)
        XCTAssertEqual(authorized.recent.map(\.id), original.recent.map(\.id))
        XCTAssertEqual(try store.load()?.accountID, "account-B")
    }

    func testUnsignedTestProcessReportsUnavailableBeforeOpeningCloudKitContainer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = CloudSyncController(store: .init(url: directory.appendingPathComponent("state.json")),
                                             onRemote: { _ in }, onStatus: { _ in })
        do { _ = try await controller.prepare(.init(recent: [], favorites: []), reauthorize: true); XCTFail("Unsigned test has no CloudKit entitlement") }
        catch { XCTAssertEqual(error as? CloudSyncError, .unavailable) }
    }

    func testRestartReconcilesLocalEditAndDeletionMissingFromJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSyncStateStore(url: directory.appendingPathComponent("state.json"))
        let old = clip()
        let removed = clip()
        let first = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        _ = try await first.prepare(.init(recent: [old, removed], favorites: []), reauthorize: true)

        let revised = Clip(id: old.id, text: "Edited after history saved", pasteboardType: old.pasteboardType,
                           sourceAppName: old.sourceAppName, sourceBundleURL: old.sourceBundleURL,
                           capturedAt: Date(), collection: .recent, order: 0)
        let restarted = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        let recovered = try await restarted.prepare(.init(recent: [revised], favorites: []), reauthorize: false)
        XCTAssertEqual(recovered.recent.map(\.text), [revised.text])
        let entries = try XCTUnwrap(store.load()?.ledger.entries)
        XCTAssertEqual(entries[old.id]?.clip?.text, revised.text)
        XCTAssertNil(entries[removed.id]?.clip)
        XCTAssertEqual(Set(try XCTUnwrap(store.load()?.ledger.pendingIDs)), [old.id, removed.id])
    }

    func testFailedRemoteHistoryWriteDoesNotCommitCloudLedger() async throws {
        enum WriteFailure: Error { case failed }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSyncStateStore(url: directory.appendingPathComponent("state.json"))
        let controller = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        let empty = HistorySnapshot(recent: [], favorites: [])
        _ = try await controller.prepare(empty, reauthorize: true)
        let remoteClip = clip()
        let remote = CloudClipEntry(id: remoteClip.id, clip: remoteClip, changedAt: Date(), origin: "other-mac")
        do {
            _ = try await controller.mergeRemote([remote], into: empty, apply: { _ in throw WriteFailure.failed })
            XCTFail("Expected history write failure")
        } catch WriteFailure.failed {}
        XCTAssertNil(try store.load()?.ledger.entries[remoteClip.id])
    }

    func testFetchedRecordKeepsServerFieldsForLaterEdit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSyncStateStore(url: directory.appendingPathComponent("state.json"))
        let controller = CloudSyncController(store: store, accountIdentity: { "account-A" }, onRemote: { _ in }, onStatus: { _ in })
        _ = try await controller.prepare(.init(recent: [], favorites: []), reauthorize: true)
        let downloaded = clip()
        let entry = CloudClipEntry(id: downloaded.id, clip: downloaded, changedAt: Date(), origin: "other-mac")
        let record = try CloudRecordCodec.record(for: entry, zoneID: CKRecordZone.ID(zoneName: CloudRecordCodec.zoneName), assetDirectory: directory)

        try await controller.saveFetchedSystemFields([record])

        XCTAssertNotNil(try store.load()?.systemFields[downloaded.id])
    }
}
