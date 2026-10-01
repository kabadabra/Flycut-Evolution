import XCTest
import FlycutCore
@testable import FlycutMac

@MainActor final class CapacityLimitRegressionTests: XCTestCase {
    private func clip(_ number: Int) -> Clip {
        Clip(id: UUID(), text: "Synthetic review \(number)", pasteboardType: "text", sourceAppName: "Review fixture", sourceBundleURL: nil, capturedAt: Date(timeIntervalSince1970: Double(number)), collection: .recent, order: number)
    }
    func testRepeatedRemoteBatchesKeepConfiguredCapacity() async throws {
        let domain = "flycut.review.capacity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var settings = FlycutSettings(); settings.saveMode = .never; settings.recentCapacity = 2
        SettingsStore(defaults: defaults).save(settings)
        let repository = try SQLiteHistoryRepository()
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", defaultsFactory: { _ in defaults }, repository: repository)
        var ledger = CloudSyncLedger(deviceID: "Receiver")
        let initial = HistorySnapshot(recent: [clip(0), clip(1)], favorites: [])
        try await repository.replaceAll(initial)
        _ = ledger.recordLocal(initial, at: Date(timeIntervalSince1970: 100))
        var observed: [Int] = []
        for batch in 1...3 {
            let current = try await repository.snapshot()
            let entries = (0..<2).map { index -> CloudClipEntry in
                let value = clip(batch * 10 + index)
                return .init(id: value.id, clip: value, changedAt: Date(timeIntervalSince1970: Double(100 + batch)), origin: "Other Mac")
            }
            let merged = ledger.applyRemote(entries, to: current, at: Date(timeIntervalSince1970: Double(200 + batch)))
            try await app.acceptSyncedHistory(merged)
            observed.append(app.settings.recentCapacity)
        }
        XCTAssertEqual(observed, [2, 2, 2], "Remote batches must preserve the user-selected cap of 2")
        XCTAssertEqual(SettingsStore(defaults: defaults).load().recentCapacity, 2)
    }
    func testLowerCapacityAppliesImmediately() async throws {
        let domain = "flycut.review.reduction." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var settings = FlycutSettings(); settings.saveMode = .never; settings.recentCapacity = 6
        SettingsStore(defaults: defaults).save(settings)
        let repository = try SQLiteHistoryRepository()
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", defaultsFactory: { _ in defaults }, repository: repository)
        try await repository.replaceAll(.init(recent: (0..<6).map(clip), favorites: []))
        var draft = app.settings; draft.recentCapacity = 2
        _ = try await app.applySettings(draft)
        let before = try await repository.snapshot()
        XCTAssertEqual(before.recent.count, 2)
        let after = try await app.history.capture(clip(7))
        XCTAssertEqual(after.recent.count, 2)
    }
}
