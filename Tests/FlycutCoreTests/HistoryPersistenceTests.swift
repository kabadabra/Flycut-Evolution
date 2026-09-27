import XCTest
import SQLite3
@testable import FlycutCore

final class HistoryPersistenceTests: XCTestCase {
    func testMarkerInspectionDoesNotReadClipsAndDoesNotHideCorruptMetadata() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.sqlite")
        let disk = try SQLiteHistoryRepository(url: url)
        let marker = MigrationMarker(sourceIdentity: "synthetic", importedAt: Date(timeIntervalSince1970: 123))
        try await disk.replaceAll(HistorySnapshot(recent: [], favorites: [], migration: marker))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE clips", nil, nil, nil), SQLITE_OK)
        // A full snapshot would fail here. Metadata inspection still succeeds.
        XCTAssertEqual(try SQLiteHistoryRepository.migrationMarker(at: url)?.sourceIdentity, marker.sourceIdentity)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE metadata SET value='invalid-json' WHERE key='migration'", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try SQLiteHistoryRepository.migrationMarker(at: url))
        XCTAssertEqual(sqlite3_exec(db, "DELETE FROM metadata WHERE key='migration'", nil, nil, nil), SQLITE_OK)
        XCTAssertNil(try SQLiteHistoryRepository.migrationMarker(at: url))
    }
    func testMarkerInspectionDoesNotCreateAbsentDatabase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("history.sqlite")
        XCTAssertNil(try SQLiteHistoryRepository.migrationMarker(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    func testMalformedSavedMetadataSurvivesRestoreFailureAndQuitSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("history.sqlite")
        let disk = try SQLiteHistoryRepository(url: url)
        let clip = Clip(id: UUID(), text: "synthetic recoverable text", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        try await disk.replaceAll(HistorySnapshot(recent: [clip], favorites: []))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO metadata(key,value) VALUES('migration','malformed-json')", nil, nil, nil), SQLITE_OK)
        let working = try SQLiteHistoryRepository()
        let persistence = HistoryPersistence(destination: disk)
        do { try await persistence.restore(into: working); XCTFail("Expected malformed metadata read failure") } catch {}
        let saved = try await persistence.save(HistorySnapshot(recent: [], favorites: []))
        XCTAssertFalse(saved, "Quit must never replace an unread destination")
        XCTAssertEqual(sqlite3_exec(db, "DELETE FROM metadata WHERE key='migration'", nil, nil, nil), SQLITE_OK)
        let recovered = try await disk.snapshot()
        XCTAssertEqual(recovered.recent.map(\.text), ["synthetic recoverable text"])
    }
    func testSuccessfulRestorePermitsSavingAndUnattemptedRestoreDoesNot() async throws {
        let disk = try SQLiteHistoryRepository(), working = try SQLiteHistoryRepository()
        let persistence = HistoryPersistence(destination: disk)
        let before = try await persistence.save(HistorySnapshot(recent: [], favorites: []))
        XCTAssertFalse(before)
        try await persistence.restore(into: working)
        let after = try await persistence.save(HistorySnapshot(recent: [], favorites: []))
        XCTAssertTrue(after)
    }

    func testExternalHistoryChangeCannotBeOverwrittenByStaleQuitSnapshot() async throws {
        let disk = try SQLiteHistoryRepository(), working = try SQLiteHistoryRepository()
        let persistence = HistoryPersistence(destination: disk)
        try await persistence.restore(into: working)
        let recovered = HistorySnapshot(recent: (0..<50).map { index in
            Clip(id: UUID(), text: "Recovered \(index)", pasteboardType: "text", sourceAppName: nil,
                 sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: index)
        }, favorites: [])
        try await disk.replaceAll(recovered)
        let stale = HistorySnapshot(recent: [Clip(id: UUID(), text: "new capture", pasteboardType: "text",
                                                  sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil,
                                                  collection: .recent, order: 0)], favorites: [])

        do {
            _ = try await persistence.save(stale)
            XCTFail("A stale session must not replace history written after restore")
        } catch {
            XCTAssertEqual(error as? HistoryError, .staleSnapshot)
        }
        let final = try await disk.snapshot()
        XCTAssertEqual(final, recovered)
    }
}
