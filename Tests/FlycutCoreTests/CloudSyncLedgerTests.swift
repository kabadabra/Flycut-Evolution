import Foundation
import XCTest
@testable import FlycutCore

final class CloudSyncLedgerTests: XCTestCase {
    private func clip(_ text: String, app: String = "Source", id: UUID = UUID(), at time: TimeInterval = 10) -> Clip {
        Clip(id: id, text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: app,
             sourceBundleURL: nil, capturedAt: Date(timeIntervalSince1970: time), collection: .recent, order: 0)
    }

    func testOfflineCopyAndReconnectTransfersExactlyOneStableRecord() {
        let copied = clip("offline")
        var first = CloudSyncLedger(deviceID: "Mac-A")
        var second = CloudSyncLedger(deviceID: "Mac-B")
        let local = HistorySnapshot(recent: [copied], favorites: [])
        XCTAssertEqual(first.recordLocal(local, at: Date(timeIntervalSince1970: 20)), [copied.id])
        XCTAssertEqual(first.recordLocal(local, at: Date(timeIntervalSince1970: 21)), [])
        let received = second.applyRemote(first.pendingEntries, to: .init(recent: [], favorites: []), at: Date(timeIntervalSince1970: 22))
        XCTAssertEqual(received.recent.map(\.id), [copied.id])
        XCTAssertEqual(second.pendingEntries.count, 0)
    }

    func testFormattedClipSurvivesCloudEncodingAndRemoteMerge() throws {
        let rtf = Data("{\\rtf1\\ansi\\b Rich}".utf8)
        let original = clip("Rich")
        let rich = Clip(id: original.id, text: original.text, pasteboardType: original.pasteboardType,
                        sourceAppName: original.sourceAppName, sourceBundleURL: original.sourceBundleURL,
                        capturedAt: original.capturedAt, collection: .recent, order: 0, formattedRTF: rtf)
        var sender = CloudSyncLedger(deviceID: "A")
        var receiver = CloudSyncLedger(deviceID: "B")
        _ = sender.recordLocal(.init(recent: [rich], favorites: []), at: Date(timeIntervalSince1970: 20))
        let decoded = try JSONDecoder().decode([CloudClipEntry].self, from: JSONEncoder().encode(sender.pendingEntries))
        let received = receiver.applyRemote(decoded, to: .init(recent: [], favorites: []), at: Date(timeIntervalSince1970: 21))
        XCTAssertEqual(received.recent.first?.formattedRTF, rtf)
        sender.clearPending()
        _ = sender.recordLocal(.init(recent: [original], favorites: []), at: Date(timeIntervalSince1970: 22))
        XCTAssertEqual(sender.pendingEntries.first?.clip?.formattedRTF, nil)
    }

    func testSameAppCopiesOnTwoMacsConvergeAndTombstoneLoser() {
        let older = clip("same", id: UUID(), at: 10)
        let newer = clip("same", id: UUID(), at: 30)
        var first = CloudSyncLedger(deviceID: "Mac-A")
        var second = CloudSyncLedger(deviceID: "Mac-B")
        _ = first.recordLocal(.init(recent: [older], favorites: []), at: Date(timeIntervalSince1970: 11))
        _ = second.recordLocal(.init(recent: [newer], favorites: []), at: Date(timeIntervalSince1970: 31))
        let onFirst = first.applyRemote(second.pendingEntries, to: .init(recent: [older], favorites: []), at: Date(timeIntervalSince1970: 32))
        XCTAssertEqual(onFirst.recent.map(\.id), [newer.id])
        XCTAssertTrue(first.pendingEntries.contains { $0.id == older.id && $0.clip == nil })
        let onSecond = second.applyRemote(first.pendingEntries, to: .init(recent: [newer], favorites: []), at: Date(timeIntervalSince1970: 33))
        XCTAssertEqual(onSecond.recent.map(\.id), [newer.id])
    }

    func testDeleteOnOneMacDoesNotResurrectFromOfflineMac() {
        let original = clip("delete me")
        var first = CloudSyncLedger(deviceID: "Mac-A")
        var second = CloudSyncLedger(deviceID: "Mac-B")
        _ = first.recordLocal(.init(recent: [original], favorites: []), at: Date(timeIntervalSince1970: 20))
        let remote = first.pendingEntries
        let copy = second.applyRemote(remote, to: .init(recent: [], favorites: []), at: Date(timeIntervalSince1970: 21))
        XCTAssertEqual(copy.recent.count, 1)
        _ = first.recordLocal(.init(recent: [], favorites: []), at: Date(timeIntervalSince1970: 30))
        let afterDelete = second.applyRemote(first.pendingEntries, to: copy, at: Date(timeIntervalSince1970: 31))
        XCTAssertTrue(afterDelete.recent.isEmpty)
        XCTAssertEqual(second.recordLocal(afterDelete, at: Date(timeIntervalSince1970: 32)), [])
    }

    func testFavoriteAndCapacityChangesAreSyncedWithoutRewritingOtherRows() {
        let firstClip = clip("first")
        let secondClip = clip("second")
        var ledger = CloudSyncLedger(deviceID: "Mac-A")
        let both = HistorySnapshot(recent: [firstClip, secondClip], favorites: [])
        _ = ledger.recordLocal(both, at: Date(timeIntervalSince1970: 20))
        ledger.clearPending()
        let favorite = Clip(id: firstClip.id, text: firstClip.text, pasteboardType: firstClip.pasteboardType,
                            sourceAppName: firstClip.sourceAppName, sourceBundleURL: firstClip.sourceBundleURL,
                            capturedAt: firstClip.capturedAt, collection: .favorite, order: 0)
        let next = HistorySnapshot(recent: [], favorites: [favorite])
        XCTAssertEqual(Set(ledger.recordLocal(next, at: Date(timeIntervalSince1970: 30))), Set([firstClip.id, secondClip.id]))
        XCTAssertNil(ledger.entries[secondClip.id]?.clip)
        XCTAssertEqual(ledger.entries[firstClip.id]?.clip?.collection, .favorite)
    }

    func testLedgerPersistsPendingChangesAndIgnoresOrderRenumbering() throws {
        let firstClip = clip("first")
        let secondClip = clip("second")
        var ledger = CloudSyncLedger(deviceID: "Mac-A")
        let initial = HistorySnapshot(recent: [firstClip, secondClip], favorites: [])
        _ = ledger.recordLocal(initial, at: Date(timeIntervalSince1970: 20))
        let restored = try JSONDecoder().decode(CloudSyncLedger.self, from: JSONEncoder().encode(ledger))
        var resumed = restored
        let reordered = HistorySnapshot(recent: [secondClip, firstClip], favorites: [])
        XCTAssertEqual(resumed.recordLocal(reordered, at: Date(timeIntervalSince1970: 21)), [])
        XCTAssertEqual(resumed.pendingEntries.count, 2)
    }

    func testRestartAbsorbsOnlyUntrackedLocalClipBeforeReplayingLedger() {
        let synced = clip("synced")
        let unsynced = clip("saved just before crash")
        var ledger = CloudSyncLedger(deviceID: "Mac-A")
        _ = ledger.recordLocal(.init(recent: [synced], favorites: []), at: Date(timeIntervalSince1970: 20))
        ledger.clearPending()
        let disk = HistorySnapshot(recent: [unsynced], favorites: [])
        XCTAssertEqual(ledger.absorbUntrackedLocal(disk, at: Date(timeIntervalSince1970: 30)), [unsynced.id])
        let recovered = ledger.applyRemote([], to: disk, at: Date(timeIntervalSince1970: 31))
        XCTAssertEqual(Set(recovered.recent.map(\.id)), Set([synced.id, unsynced.id]))
    }
}
