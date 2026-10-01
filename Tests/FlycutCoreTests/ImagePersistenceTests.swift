import XCTest
@testable import FlycutCore
final class ImagePersistenceTests: XCTestCase {
    func testFailedImageWriteLeavesNoAssetOrEntry() async throws {
        let repo = try SQLiteHistoryRepository()
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "bad", width: 0, height: 1, byteCount: 1))
        do { _ = try await repo.applyImage(.init(hash: "bad", png: Data([1])), clip: clip, budgetBytes: 10); XCTFail() } catch {}
        let snapshot = try await repo.snapshot(), bytes = try await repo.imageData(for: "bad")
        XCTAssertTrue(snapshot.recent.isEmpty); XCTAssertNil(bytes)
    }
    func testNeverAndOnQuitHaveNoImplicitDiskWrites() async throws {
        let working = try SQLiteHistoryRepository(), disk = try SQLiteHistoryRepository()
        let gate = HistoryPersistence(destination: disk)
        try await gate.restore(into: working)
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "one", width: 1, height: 1, byteCount: 1))
        let snapshot = try await working.applyImage(.init(hash: "one", png: Data([1])), clip: clip, budgetBytes: 10)
        let before = try await disk.imageData(for: "one")
        XCTAssertNil(before)
        _ = try await gate.save(snapshot, assets: working.exportAssets(for: snapshot))
        let after = try await disk.imageData(for: "one")
        XCTAssertEqual(after, Data([1]))
    }
}
