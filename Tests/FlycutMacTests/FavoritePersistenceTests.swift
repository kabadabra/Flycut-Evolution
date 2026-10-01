import XCTest
import SQLite3
@testable import FlycutCore
@testable import FlycutMac

@MainActor final class FavoritePersistenceTests: XCTestCase {
    func testDurableFailureRollsBackWorkingAndSavedFavorites() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.sqlite")
        let disk = try SQLiteHistoryRepository(url: url)
        let clip = Clip(id: UUID(), text: "saved", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil,
                        capturedAt: nil, collection: .favorite, order: 0)
        try await disk.replaceAll(.init(recent: [], favorites: [clip]))
        let failing = try SQLiteHistoryRepository(url: url, permissionMaintenance: { _ in throw HistoryError.database("Denied") }, metadataStep: sqlite3_step)
        let memory = try SQLiteHistoryRepository()
        let persistence = HistoryPersistence(destination: failing)
        try await persistence.restore(into: memory)
        let baseline = try await memory.snapshot()
        let history = HistoryService(repository: memory)
        do {
            _ = try await FavoriteMutation.perform(repository: memory, operation: {
                _ = try await history.updateFavorite(id: clip.id, edit: .init(name: "New", text: "changed"))
            }, persist: { snapshot in _ = try await persistence.save(snapshot) })
            XCTFail("Failed durable save must not return a publishable snapshot")
        } catch {}
        let local = try await memory.snapshot(), saved = try await disk.snapshot()
        XCTAssertEqual(local, baseline); XCTAssertEqual(saved, baseline)
    }
    func testCreatingFavoriteRollsBackEvictedImageAssetsOnSaveFailure() async throws {
        let repo = try SQLiteHistoryRepository()
        func image(_ hash: String, _ collection: CollectionKind) -> Clip {
            Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: collection, order: 0, image: .init(assetHash: hash, width: 1, height: 1, byteCount: 3))
        }
        let old = image("old", .favorite), incoming = image("new", .recent)
        let baseline = HistorySnapshot(recent: [incoming], favorites: [old])
        try await repo.replaceAll(baseline, assets: [.init(hash: "old", png: Data([1,2,3])), .init(hash: "new", png: Data([4,5,6]))])
        let history = HistoryService(repository: repo, favoriteCapacity: 1)
        do {
            _ = try await FavoriteMutation.perform(repository: repo, operation: { _ = try await history.favorite(id: incoming.id) }, persist: { _ in throw HistoryError.database("Disk full") })
            XCTFail("Failed save must not publish the new favorite")
        } catch {}
        let restored = try await repo.snapshot(), asset = try await repo.imageData(for: "old")
        XCTAssertEqual(restored, baseline); XCTAssertEqual(asset, Data([1,2,3]))
    }

}
