import XCTest
@testable import FlycutCore
final class ImageHistoryTests: XCTestCase {
    private func clip(_ hash: String, bytes: Int = 3, kind: CollectionKind = .recent) -> Clip {
        Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: Date(), collection: kind, order: 0,
             image: .init(assetHash: hash, width: 1, height: 1, byteCount: bytes))
    }
    func testLazyAssetsRoundTripAndReferenceCleanup() async throws {
        let repo = try SQLiteHistoryRepository()
        let a = ImageAsset(hash: "one", png: Data([1,2,3]))
        let first = clip("one")
        let result = try await repo.applyImage(a, clip: first, budgetBytes: 3)
        XCTAssertEqual(result.recent.first?.image?.assetHash, "one")
        let second = clip("one", kind: .favorite)
        _ = try await repo.apply(.insert(second))
        _ = try await repo.apply(.delete(first.id))
        let bytes = try await repo.imageData(for: "one")
        XCTAssertEqual(bytes, a.png)
        _ = try await repo.apply(.delete(second.id))
        let removed = try await repo.imageData(for: "one")
        XCTAssertNil(removed)
    }
    func testBudgetEvictsRecentsAndProtectsFavorites() async throws {
        let repo = try SQLiteHistoryRepository()
        _ = try await repo.applyImage(.init(hash: "one", png: Data([1,2,3])), clip: clip("one"), budgetBytes: 3)
        let second = try await repo.applyImage(.init(hash: "two", png: Data([4,5,6])), clip: clip("two"), budgetBytes: 3)
        XCTAssertEqual(second.recent.map { $0.image!.assetHash }, ["two"])
        let history = HistoryService(repository: repo)
        _ = try await history.favorite(id: second.recent[0].id)
        do {
            _ = try await repo.applyImage(.init(hash: "three", png: Data([7,8,9])), clip: clip("three"), budgetBytes: 3)
            XCTFail("Favorites must prevent admission")
        } catch {}
        let final = try await repo.snapshot()
        XCTAssertEqual(final.favorites.first?.image?.assetHash, "two")
    }
    func testAssetsTravelWithSaveAndRestore() async throws {
        let source = try SQLiteHistoryRepository(), disk = try SQLiteHistoryRepository(), restored = try SQLiteHistoryRepository()
        let persistence = HistoryPersistence(destination: disk)
        try await persistence.restore(into: source)
        let snapshot = try await source.applyImage(.init(hash: "one", png: Data([1,2,3])), clip: clip("one"), budgetBytes: 3)
        let assets = try await source.exportAssets(for: snapshot)
        let saved = try await persistence.save(snapshot, assets: assets)
        XCTAssertTrue(saved)
        try await HistoryPersistence(destination: disk).restore(into: restored)
        let bytes = try await restored.imageData(for: "one")
        XCTAssertEqual(bytes, Data([1,2,3]))
    }
    func testLoweringBudgetKeepsFavoritesAndEvictsOnlyRecentImages() async throws {
        let repo = try SQLiteHistoryRepository()
        let favorite = clip("favorite", kind: .favorite)
        _ = try await repo.applyImage(.init(hash: "favorite", png: Data([1,2,3])), clip: clip("favorite"), budgetBytes: 6)
        let service = HistoryService(repository: repo)
        let initial = try await repo.snapshot()
        _ = try await service.favorite(id: initial.recent[0].id)
        _ = try await repo.applyImage(.init(hash: "recent", png: Data([4,5,6])), clip: clip("recent"), budgetBytes: 6)
        let fits = try await repo.trimImageBudget(to: 2)
        XCTAssertFalse(fits)
        let result = try await repo.snapshot()
        XCTAssertEqual(result.favorites.count, 1)
        XCTAssertTrue(result.recent.isEmpty)
        _ = favorite
    }
    func testImageFavoriteRenameAndOrderRetainMetadata() async throws {
        let repo = try SQLiteHistoryRepository()
        let first = clip("one")
        _ = try await repo.applyImage(.init(hash: "one", png: Data([1,2,3])), clip: first, budgetBytes: 3)
        let service = HistoryService(repository: repo)
        _ = try await service.favorite(id: first.id)
        let snapshot = try await service.updateFavorite(id: first.id, edit: .init(name: "Screenshot", text: "", shortcut: 2))
        XCTAssertEqual(snapshot.favorites[0].image?.assetHash, "one")
        XCTAssertEqual(snapshot.favorites[0].withOrder(5).image?.assetHash, "one")
    }
}
