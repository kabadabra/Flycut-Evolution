import XCTest
@testable import FlycutCore
final class EvictionArchiveTests: XCTestCase, @unchecked Sendable {
    func testFavoriteCapacityEvictionUsesPrivateFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let history = HistoryService(repository: repository, favoriteCapacity: 1, archive: EvictionArchive(directory: directory), archiveFavorites: true)
        var ids: [UUID] = []
        for index in 0..<2 {
            let clip = Clip(id: UUID(), text: "Synthetic favorite \(index)", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
            ids.append(clip.id)
            try await history.capture(clip); try await history.favorite(id: clip.id)
        }
        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.favorites.map(\.id), [ids[1]])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try String(contentsOf: files[0], encoding: .utf8), "Synthetic favorite 0")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testOnlyCapacityEvictionsAreArchivedAndFailurePreventsLoss() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let archive = EvictionArchive(directory: directory)
        let history = HistoryService(repository: repository, recentCapacity: 1, archive: archive, archiveRecents: true)
        let a = Clip(id: UUID(), text: "Synthetic first", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let b = Clip(id: UUID(), text: "Synthetic second", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        try await history.capture(a); try await history.capture(b)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try String(contentsOf: files[0], encoding: .utf8), a.text)
        try await history.delete(id: b.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        let bad = HistoryService(repository: repository, recentCapacity: 1, archive: EvictionArchive(directory: files[0]), archiveRecents: true)
        try await bad.capture(a)
        do { try await bad.capture(b); XCTFail("Archive failure must preserve evicted history") } catch { }
        let kept = try await repository.snapshot()
        XCTAssertEqual(kept.recent.map(\.id), [a.id])
    }
}
