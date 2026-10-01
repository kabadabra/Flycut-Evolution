import XCTest
import SQLite3
@testable import FlycutCore

final class FavoriteManagementTests: XCTestCase {
    private func clip(_ text: String, rank: Int = 0, slot: Int? = nil, rtf: Data? = nil) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: "Test", sourceBundleURL: nil,
             capturedAt: Date(timeIntervalSince1970: 10), collection: .favorite, order: rank, formattedRTF: rtf,
             favoriteMetadata: .init(name: "Alias", shortcut: slot, rank: rank))
    }
    func testFavoriteMetadataSurvivesRestartAndBackup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.sqlite")
        let favorite = clip("  saved\n🦋", rank: 3, slot: 2, rtf: Data([1,2]))
        let db = try SQLiteHistoryRepository(url: url)
        try await db.replaceAll(.init(recent: [], favorites: [favorite]))
        let reopened = try SQLiteHistoryRepository(url: url)
        let value = try await reopened.snapshot()
        XCTAssertEqual(value.favorites[0].favoriteMetadata, .init(name: "Alias", shortcut: 2, rank: 3))
        XCTAssertEqual(value.favorites[0].text, "  saved\n🦋")
        let backup = try JSONDecoder().decode(HistorySnapshot.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(backup, value)
        let memory = try SQLiteHistoryRepository()
        try await HistoryPersistence(destination: reopened).restore(into: memory)
        let restored = try await memory.snapshot()
        XCTAssertEqual(restored, value)
    }
    func testLegacySchemasUpgradeWithoutChangingClips() async throws {
        for version in [1,2] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("history.sqlite")
            let id = UUID()
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
            let rich = version == 2 ? ", formatted_rtf BLOB" : ""
            let sql = "CREATE TABLE clips(id TEXT PRIMARY KEY,text TEXT,pasteboard_type TEXT,source_app_name TEXT,source_bundle_url TEXT,captured_at REAL,collection TEXT,position INTEGER\(rich)); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT); INSERT INTO clips(id,text,pasteboard_type,collection,position) VALUES('\(id.uuidString)','saved','text','favorite',0); PRAGMA user_version=\(version);"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            sqlite3_close(db)
            let store = try SQLiteHistoryRepository(url: url)
            let value = try await store.snapshot()
            XCTAssertEqual(value.favorites.first?.id, id)
            XCTAssertEqual(value.favorites.first?.text, "saved")
            XCTAssertNil(value.favorites.first?.favoriteMetadata)
        }
    }
    func testLegacyJSONWithoutFavoriteMetadataDecodes() throws {
        let original = clip("old")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "favoriteMetadata")
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.favoriteMetadata)
        XCTAssertEqual(decoded.text, "old")
    }
    func testRenamePreservesRTFAndTextEditClearsRTF() async throws {
        let db = try SQLiteHistoryRepository()
        let original = clip("old", rtf: Data([1]))
        try await db.replaceAll(.init(recent: [], favorites: [original]))
        let service = HistoryService(repository: db)
        let renamed = try await service.updateFavorite(id: original.id, edit: .init(name: "New", text: "old", shortcut: 3))
        XCTAssertEqual(renamed.favorites.first?.formattedRTF, Data([1]))
        let edited = try await service.updateFavorite(id: original.id, edit: .init(name: "New", text: "  new\n", shortcut: 3))
        XCTAssertEqual(edited.favorites.first?.text, "  new\n")
        XCTAssertNil(edited.favorites.first?.formattedRTF)
        XCTAssertEqual(edited.favorites.first?.favoriteMetadata?.name, "New")
    }
    func testInvalidEditLeavesSavedSnapshotUnchanged() async throws {
        let db = try SQLiteHistoryRepository()
        let a = clip("first", slot: 1), b = clip("second", rank: 1, slot: 2)
        try await db.replaceAll(.init(recent: [], favorites: [a,b]))
        let baseline = try await db.snapshot()
        let service = HistoryService(repository: db)
        for edit in [FavoriteEdit(name: "", text: " \n"), .init(name: String(repeating: "x", count: 201), text: "valid"),
                     .init(name: "", text: "valid", shortcut: 10), .init(name: "", text: "valid", shortcut: 2)] {
            do { _ = try await service.updateFavorite(id: a.id, edit: edit); XCTFail("Invalid edit accepted") } catch {}
            let after = try await db.snapshot()
            XCTAssertEqual(after, baseline)
        }
        do { _ = try await service.updateFavorite(id: UUID(), edit: .init(name: "", text: "valid")); XCTFail("Missing ID accepted") } catch {}
    }
    func testReorderKeepsShortcutAndSurvivesSync() async throws {
        let db = try SQLiteHistoryRepository()
        let a = clip("first", slot: 1), b = clip("second", rank: 1, slot: 2)
        try await db.replaceAll(.init(recent: [], favorites: [a,b]))
        let service = HistoryService(repository: db)
        var sender = CloudSyncLedger(deviceID: "a"), receiver = CloudSyncLedger(deviceID: "b")
        let original = try await db.snapshot()
        sender.recordLocal(original, at: Date(timeIntervalSince1970: 10))
        let moved = try await service.moveFavorite(id: b.id, offset: -1)
        sender.recordLocal(moved, at: Date(timeIntervalSince1970: 20))
        let received = receiver.applyRemote(sender.pendingEntries, to: .init(recent: [], favorites: []), at: Date())
        XCTAssertEqual(received.favorites.map(\.id), [b.id,a.id])
        XCTAssertEqual(received.favorites.map { $0.favoriteMetadata?.shortcut }, [2,1])
        XCTAssertEqual(FavoriteShortcuts.resolve(slot: 1, favorites: received.favorites), .clip(a.id))
        do { _ = try await service.moveFavorite(id: b.id, offset: -1); XCTFail("Boundary accepted") } catch {}
    }
    func testRemoteShortcutConflictDoesNotChooseEitherFavorite() {
        let a = clip("a", slot: 1), b = clip("b", slot: 1)
        var one = CloudSyncLedger(deviceID: "one"), two = CloudSyncLedger(deviceID: "two")
        let entries = [a,b].map { CloudClipEntry(id: $0.id, clip: $0, changedAt: Date(timeIntervalSince1970: 1), origin: "source") }
        let first = one.applyRemote(entries, to: .init(recent: [], favorites: []), at: Date())
        let second = two.applyRemote(entries.reversed(), to: .init(recent: [], favorites: []), at: Date())
        XCTAssertEqual(first.favorites.map(\.id), second.favorites.map(\.id))
        XCTAssertEqual(FavoriteShortcuts.resolve(slot: 1, favorites: first.favorites), .conflict)
        XCTAssertEqual(FavoriteShortcuts.resolve(slot: 9, favorites: first.favorites), .missing)
    }

}
