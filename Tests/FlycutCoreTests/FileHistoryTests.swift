import XCTest
@testable import FlycutCore

final class FileHistoryTests: XCTestCase {
    private func fileClip(_ path: String) throws -> Clip {
        let clip = Clip(id: UUID(), text: "same.pdf", pasteboardType: "public.file-url", sourceAppName: "Finder", sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as! [String: Any]
        object["files"] = [["urlString": URL(fileURLWithPath: path).absoluteString]]
        return try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func encodedFiles(_ clip: Clip) throws -> [[String: String]]? {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as! [String: Any]
        return object["files"] as? [[String: String]]
    }
    func testFilePathsSurviveDatabaseAndFavoriteChanges() async throws {
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let history = HistoryService(repository: repository)
        let clip = try fileClip("/tmp/folder A/same.pdf")
        _ = try await history.capture(clip)
        let snapshot = try await history.favorite(id: clip.id)
        let favorite = try XCTUnwrap(snapshot.favorites.first)
        XCTAssertEqual(try encodedFiles(favorite)?.first?["urlString"], "file:///tmp/folder%20A/same.pdf")
        let moved = favorite.withOrder(9).withFavoriteMetadata(.init(name: "Document", rank: 9))
        XCTAssertEqual(try encodedFiles(moved), try encodedFiles(clip))
    }
    func testFilesWithSameNameInDifferentDirectoriesAreNotDeduplicated() async throws {
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let history = HistoryService(repository: repository)
        _ = try await history.capture(fileClip("/tmp/A/same.pdf"))
        let snapshot = try await history.capture(fileClip("/tmp/B/same.pdf"))
        XCTAssertEqual(snapshot.recent.count, 2)
        var ledger = CloudSyncLedger(deviceID: "test")
        ledger.recordLocal(snapshot, at: Date())
        XCTAssertEqual(ledger.applyRemote([], to: snapshot, at: Date()).recent.count, 2)
    }
    func testFileExportAndEvictionArchiveKeepPaths() throws {
        let clip = try fileClip("/tmp/folder A/same.pdf")
        let export = try ClipExport.make([clip], assets: [])
        XCTAssertEqual(export.filename, "Flycut.json")
        let collection = try JSONDecoder().decode(ClipExport.Collection.self, from: export.data)
        XCTAssertEqual(try encodedFiles(collection.clips[0]), try encodedFiles(clip))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try EvictionArchive(directory: directory).save([clip])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "/tmp/folder A/same.pdf")
    }
    func testFilePathsAreSearchableAndInvalidRemoteReferencesAreRejected() throws {
        let clip = try fileClip("/tmp/folder A/same.pdf")
        XCTAssertTrue(clip.searchableText.contains("/tmp/folder A/same.pdf"))
        XCTAssertThrowsError(try ClipFile(url: URL(string: "https://example.com/file.pdf")!))
        XCTAssertThrowsError(try ClipFile(url: URL(string: "file://remote-server/share/file.pdf")!))
    }

    func testMergeAllDoesNotReturnOrConsumeFilesAsText() async throws {
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let history = HistoryService(repository: repository)
        let clip = try fileClip("/tmp/folder A/same.pdf")
        _ = try await history.capture(clip)
        let result = try await history.mergeAll()
        XCTAssertNil(result)
        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.recent.map(\.id), [clip.id])
    }

}
