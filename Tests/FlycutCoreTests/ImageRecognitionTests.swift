import XCTest
@testable import FlycutCore
final class ImageRecognitionTests: XCTestCase {
    func testRecognizedTextSearchAndDeletedResultGuard() async throws {
        let repo = try SQLiteHistoryRepository(), service = HistoryService(repository: try SQLiteHistoryRepository())
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "a", width: 1, height: 1, byteCount: 1))
        _ = try await repo.applyImage(.init(hash: "a", png: Data([1])), clip: clip, budgetBytes: 10)
        let history = HistoryService(repository: repo)
        let snapshot = try await history.updateRecognition(id: clip.id, assetHash: "a", text: "Résumé example", state: .recognized)
        XCTAssertEqual(ClipSearch.search("resume", in: snapshot.recent).first?.clip.id, clip.id)
        _ = try await history.delete(id: clip.id)
        do { _ = try await history.updateRecognition(id: clip.id, assetHash: "a", text: "stale", state: .recognized); XCTFail() } catch {}
        _ = service
    }
}
