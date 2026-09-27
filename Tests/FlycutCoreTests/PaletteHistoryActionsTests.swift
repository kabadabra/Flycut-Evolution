import XCTest
@testable import FlycutCore

final class PaletteHistoryActionsTests: XCTestCase {
    func testClearRecentsKeepsFavoritesAndDeleteUsesStableID() async throws {
        let repository = try SQLiteHistoryRepository()
        let recent = Clip(id: UUID(), text: "recent", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let favorite = Clip(id: UUID(), text: "favorite", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .favorite, order: 0)
        try await repository.replaceAll(HistorySnapshot(recent: [recent], favorites: [favorite]))
        let service = HistoryService(repository: repository)
        let cleared = try await service.clearRecents()
        XCTAssertTrue(cleared.recent.isEmpty)
        XCTAssertEqual(cleared.favorites.map(\.id), [favorite.id])
        let deleted = try await service.delete(id: favorite.id)
        XCTAssertTrue(deleted.favorites.isEmpty)
    }
    func testMoveToTopPreservesCollectionAndText() async throws {
        let repository = try SQLiteHistoryRepository()
        let a = Clip(id: UUID(), text: "A", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let b = Clip(id: UUID(), text: "B", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 1)
        try await repository.replaceAll(HistorySnapshot(recent: [a,b], favorites: []))
        let service = HistoryService(repository: repository)
        let moved = try await service.moveToTop(id: b.id)
        XCTAssertEqual(moved.recent.map(\.text), ["B", "A"])
    }
}
