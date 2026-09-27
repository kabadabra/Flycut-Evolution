import Foundation
import XCTest
@testable import FlycutCore
import SQLite3

final class HistoryRepositoryTests: XCTestCase {
    private func clip(_ text: String, id: UUID = UUID(), collection: CollectionKind = .recent, order: Int = 0) -> Clip {
        Clip(id: id, text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: "Test", sourceBundleURL: "file:///Applications/Test.app", capturedAt: Date(timeIntervalSince1970: 123), collection: collection, order: order)
    }

    private func repository() throws -> SQLiteHistoryRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SQLiteHistoryRepository(url: directory.appendingPathComponent("history.sqlite"))
    }

    func testInsertPreservesNewestFirstOrderAndMetadataAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let first = clip("first\n")
        let second = clip("second")
        let store = try SQLiteHistoryRepository(url: url)
        _ = try await store.apply(.insert(first))
        _ = try await store.apply(.insert(second))
        let reopened = try SQLiteHistoryRepository(url: url)
        let values = try await reopened.snapshot().recent
        XCTAssertEqual(values.map(\.id), [second.id, first.id])
        XCTAssertEqual(values.map(\.order), [0, 1])
        XCTAssertEqual(values[1].text, "first\n")
        XCTAssertEqual(values[1].sourceAppName, "Test")
        XCTAssertEqual(values[1].sourceBundleURL, "file:///Applications/Test.app")
        XCTAssertEqual(values[1].capturedAt, Date(timeIntervalSince1970: 123))
    }

    func testFormattedRTFRoundTripsAcrossRepositoryRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let rtf = Data("{\\rtf1\\ansi \n\\b Styled\\b0}".utf8)
        let source = Clip(id: UUID(), text: "Styled", pasteboardType: "public.utf8-plain-text",
                          sourceAppName: "Test", sourceBundleURL: nil, capturedAt: nil,
                          collection: .recent, order: 0, formattedRTF: rtf)
        let store = try SQLiteHistoryRepository(url: url)
        _ = try await store.apply(.insert(source))
        let reopened = try SQLiteHistoryRepository(url: url)
        let persisted = try await reopened.snapshot()
        XCTAssertEqual(persisted.recent.first?.formattedRTF, rtf)
    }

    func testVersionOneHistoryUpgradesWithoutLosingClips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        let id = UUID()
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE clips (id TEXT PRIMARY KEY, text TEXT NOT NULL, pasteboard_type TEXT NOT NULL, source_app_name TEXT, source_bundle_url TEXT, captured_at REAL, collection TEXT NOT NULL, position INTEGER NOT NULL); CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT INTO clips VALUES ('\(id.uuidString)', 'old copy', 'public.utf8-plain-text', 'Test', NULL, NULL, 'recent', 0); PRAGMA user_version=1", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(handle), SQLITE_OK)
        let upgraded = try SQLiteHistoryRepository(url: url)
        let snapshot = try await upgraded.snapshot()
        XCTAssertEqual(snapshot.recent.first?.id, id)
        XCTAssertEqual(snapshot.recent.first?.text, "old copy")
        XCTAssertNil(snapshot.recent.first?.formattedRTF)
        var check: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &check, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(check) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(check, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
    }

    func testFavoritesRemainSeparateAndSameTextDuplicatesSurvive() async throws {
        let store = try repository()
        let first = clip("same")
        let second = clip("same")
        let favorite = clip("same", collection: .favorite)
        try await store.replaceAll(HistorySnapshot(recent: [first, second], favorites: [favorite]))
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.recent.map(\.id), [first.id, second.id])
        XCTAssertEqual(snapshot.favorites.map(\.id), [favorite.id])
        XCTAssertEqual(snapshot.recent.map(\.order), [0, 1])
    }

    func testServiceAlwaysDeduplicatesSameAppAndEvictsOldest() async throws {
        let store = try repository()
        let service = HistoryService(repository: store, recentCapacity: 2, favoriteCapacity: 2)
        let first = clip("A")
        let second = clip("B")
        let third = clip("A")
        _ = try await service.capture(first)
        _ = try await service.capture(second)
        let snapshot = try await service.capture(third)
        XCTAssertEqual(snapshot.recent.map(\.id), [first.id, second.id])
        let fourth = clip("C")
        let capped = try await service.capture(fourth)
        XCTAssertEqual(capped.recent.map(\.id), [fourth.id, first.id])
    }

    func testRecaptureUsesNewestFormattingAndFavoriteRetainsIt() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let first = clip("same")
        let latestRTF = Data("{\\rtf1\\ansi\\b same}".utf8)
        let latest = Clip(id: UUID(), text: "same", pasteboardType: first.pasteboardType,
                          sourceAppName: first.sourceAppName, sourceBundleURL: first.sourceBundleURL,
                          capturedAt: Date(), collection: .recent, order: 0, formattedRTF: latestRTF)
        _ = try await service.capture(first)
        let updated = try await service.capture(latest)
        XCTAssertEqual(updated.recent.map(\.id), [first.id])
        XCTAssertEqual(updated.recent.first?.formattedRTF, latestRTF)
        let favorite = try await service.favorite(id: first.id)
        XCTAssertEqual(favorite.favorites.first?.formattedRTF, latestRTF)
    }

    func testSearchMapsResultsBackToStableClips() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let first = clip("Café note")
        let second = clip("other")
        try await store.replaceAll(HistorySnapshot(recent: [first, second], favorites: []))
        let results = try await service.search("CAFÉ")
        XCTAssertEqual(results.map(\.id), [first.id])
    }

    func testMergeAllJoinsOldestToNewestAndReplacesRecents() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        try await store.replaceAll(HistorySnapshot(recent: [clip("new"), clip("middle"), clip("old")], favorites: []))
        let merged = try await service.mergeAll()
        XCTAssertEqual(merged?.text, "old\nmiddle\nnew")
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.recent.map(\.text), ["old\nmiddle\nnew"])
    }

    func testInvalidBatchRollsBackEveryMutation() async throws {
        let store = try repository()
        let first = clip("safe")
        _ = try await store.apply(.insert(first))
        do {
            _ = try await store.apply(.batch([.insert(clip("temporary")), .insert(first)]))
            XCTFail("Expected duplicate identifier to abort the transaction")
        } catch {
            let snapshot = try await store.snapshot()
            XCTAssertEqual(snapshot.recent.map(\.text), ["safe"])
        }
    }

    func testReplaceAllFailureLeavesOriginalSnapshot() async throws {
        let store = try repository()
        let first = clip("safe")
        try await store.replaceAll(HistorySnapshot(recent: [first], favorites: []))
        do {
            try await store.replaceAll(HistorySnapshot(recent: [first, first], favorites: []))
            XCTFail("Expected duplicate identifier to abort replacement")
        } catch {
            let after = try await store.snapshot()
            XCTAssertEqual(after.recent.map(\.text), ["safe"])
        }
    }

    func testDatabasePermissionsSchemaAndMigrationMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryRepository(url: url)
        let marker = MigrationMarker(sourceIdentity: "legacy-profile", importedAt: Date(timeIntervalSince1970: 456))
        try await store.replaceAll(HistorySnapshot(recent: [], favorites: [], migration: marker))
        let reopened = try SQLiteHistoryRepository(url: url)
        let snapshot = try await reopened.snapshot()
        XCTAssertEqual(snapshot.migration, marker)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(directoryMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
    }

    func testExactTextIncludingEmbeddedNullRoundTrips() async throws {
        let store = try repository()
        let value = "before\u{0000}after\n🦋"
        _ = try await store.apply(.insert(clip(value)))
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.recent.first?.text, value)
    }

    func testMoveDeleteAndClearDoNotAffectFavorites() async throws {
        let store = try repository()
        let first = clip("first")
        let second = clip("second")
        let favorite = clip("favorite", collection: .favorite)
        try await store.replaceAll(HistorySnapshot(recent: [first, second], favorites: [favorite]))
        _ = try await store.apply(.moveToTop(second.id))
        _ = try await store.apply(.delete(first.id))
        let snapshot = try await store.apply(.clear(.recent))
        XCTAssertTrue(snapshot.recent.isEmpty)
        XCTAssertEqual(snapshot.favorites.map(\.id), [favorite.id])
    }

    func testFavoriteMovesClipToSeparateBoundedCollection() async throws {
        let store = try repository()
        let service = HistoryService(repository: store, recentCapacity: 3, favoriteCapacity: 1)
        let first = clip("first")
        let second = clip("second")
        try await store.replaceAll(HistorySnapshot(recent: [first, second], favorites: []))
        _ = try await service.favorite(id: first.id)
        let snapshot = try await service.favorite(id: second.id)
        XCTAssertTrue(snapshot.recent.isEmpty)
        XCTAssertEqual(snapshot.favorites.map(\.id), [second.id])
        XCTAssertEqual(snapshot.favorites.first?.collection, .favorite)
        XCTAssertEqual(snapshot.favorites.first?.order, 0)
    }

    func testTopDuplicateRefreshesTimestampAndStableID() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let first = clip("same")
        let second = Clip(id: UUID(), text: "same", pasteboardType: "public.utf8-plain-text", sourceAppName: "Test", sourceBundleURL: "file:///Applications/Test.app", capturedAt: Date(timeIntervalSince1970: 456), collection: .recent, order: 0)
        _ = try await service.capture(first)
        let snapshot = try await service.capture(second)
        XCTAssertEqual(snapshot.recent.map(\.id), [first.id])
        XCTAssertEqual(snapshot.recent.first?.capturedAt, second.capturedAt)
    }

    func testSameTextFromDifferentAppsRemainsSeparate() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let first = clip("same")
        let second = Clip(id: UUID(), text: "same", pasteboardType: first.pasteboardType, sourceAppName: "Another", sourceBundleURL: "file:///Applications/Another.app", capturedAt: Date(), collection: .recent, order: 0)
        _ = try await service.capture(first)
        let result = try await service.capture(second)
        XCTAssertEqual(result.recent.map(\.id), [second.id, first.id])
    }

    func testNormalizingExistingDuplicatesKeepsNewestAndFavorites() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let newest = clip("same")
        let middle = clip("other")
        let older = clip("same")
        let favorite = clip("same", collection: .favorite)
        try await store.replaceAll(HistorySnapshot(recent: [newest, middle, older], favorites: [favorite]))
        let result = try await service.normalizeRecents()
        XCTAssertEqual(result.recent.map(\.id), [newest.id, middle.id])
        XCTAssertEqual(result.favorites.map(\.id), [favorite.id])
    }

    func testNormalizingPersistentDuplicatesWritesPrivateRecoverableBackup() async throws {
        let store = try repository()
        let service = HistoryService(repository: store)
        let original = HistorySnapshot(recent: [clip("same"), clip("same")], favorites: [clip("favorite", collection: .favorite)])
        try await store.replaceAll(original)
        let savedOriginal = try await store.snapshot()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = directory.appendingPathComponent("before-deduplication.json")
        _ = try await service.normalizeRecents(backupTo: backup)
        XCTAssertEqual(try JSONDecoder().decode(HistorySnapshot.self, from: Data(contentsOf: backup)), savedOriginal)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testConcurrentCapturesThroughOneServiceKeepBothChanges() async throws {
        let repository = SuspendedReadHistoryRepository()
        let service = HistoryService(repository: repository)
        let first = clip("first")
        let second = clip("second")
        let firstTask = Task { try await service.capture(first) }
        let secondTask = Task { try await service.capture(second) }
        _ = try await firstTask.value
        _ = try await secondTask.value
        let final = await repository.current()
        XCTAssertEqual(Set(final.recent.map(\.id)), Set([first.id, second.id]))
    }

    func testCapturePreservesMigrationWrittenByDirectRepositoryWriter() async throws {
        let repository = CoordinatedMigrationRepository()
        let service = HistoryService(repository: repository)
        let incoming = clip("new")
        let marker = MigrationMarker(sourceIdentity: "legacy", importedAt: Date(timeIntervalSince1970: 999))
        let capture = Task { try await service.capture(incoming) }
        await repository.waitForOperationStart()
        try await repository.replaceAll(HistorySnapshot(recent: [clip("imported")], favorites: [], migration: marker))
        _ = try await capture.value
        let final = await repository.current()
        XCTAssertEqual(final.migration, marker)
        XCTAssertEqual(Set(final.recent.map(\.text)), Set(["new", "imported"]))
    }

    func testPermissionMaintenanceFailureRollsBackHistoryAndMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let original = clip("original")
        let marker = MigrationMarker(sourceIdentity: "original-source", importedAt: Date(timeIntervalSince1970: 1))
        let baseline = try SQLiteHistoryRepository(url: url)
        try await baseline.replaceAll(HistorySnapshot(recent: [original], favorites: [], migration: marker))
        let failing = try SQLiteHistoryRepository(url: url, permissionMaintenance: { _ in throw ControlledHistoryFailure.permission }, metadataStep: sqlite3_step)
        do {
            try await failing.replaceAll(HistorySnapshot(recent: [clip("replacement")], favorites: [], migration: nil))
            XCTFail("Expected permission maintenance failure")
        } catch {
            let after = try await baseline.snapshot()
            XCTAssertEqual(after.recent.map(\.id), [original.id])
            XCTAssertEqual(after.migration, marker)
        }
    }

    func testMetadataStepErrorPropagatesAndCannotEraseMigrationMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let marker = MigrationMarker(sourceIdentity: "imported", importedAt: Date(timeIntervalSince1970: 2))
        let baseline = try SQLiteHistoryRepository(url: url)
        try await baseline.replaceAll(HistorySnapshot(recent: [], favorites: [], migration: marker))
        let failing = try SQLiteHistoryRepository(url: url, permissionMaintenance: { _ in }, metadataStep: { _ in SQLITE_IOERR })
        do {
            _ = try await failing.snapshot()
            XCTFail("Expected metadata read failure")
        } catch {
            XCTAssertNotNil(error as? HistoryError)
        }
        do {
            _ = try await failing.apply(.insert(clip("must-not-commit")))
            XCTFail("Expected apply to fail before modifying history")
        } catch {
            let after = try await baseline.snapshot()
            XCTAssertEqual(after.migration, marker)
            XCTAssertTrue(after.recent.isEmpty)
        }
    }
}

private enum ControlledHistoryFailure: Error { case permission }

private actor SuspendedReadHistoryRepository: HistoryRepository {
    private var value = HistorySnapshot(recent: [], favorites: [])
    private var firstRead: CheckedContinuation<HistorySnapshot, Never>?

    func snapshot() async throws -> HistorySnapshot {
        if let firstRead {
            self.firstRead = nil
            firstRead.resume(returning: value)
            return value
        }
        return await withCheckedContinuation { firstRead = $0 }
    }

    func apply(_ change: HistoryChange) async throws -> HistorySnapshot {
        throw HistoryError.database("Unsupported test operation")
    }

    func replaceAll(_ snapshot: HistorySnapshot) async throws { value = snapshot }

    func update(_ body: @Sendable (inout HistorySnapshot) throws -> Void) async throws -> HistorySnapshot {
        try body(&value)
        return value
    }

    func current() -> HistorySnapshot { value }
}

private actor CoordinatedMigrationRepository: HistoryRepository {
    private var value = HistorySnapshot(recent: [], favorites: [])
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func waitForOperationStart() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    private func waitForMigration() async {
        started = true
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { release = $0 }
    }

    func snapshot() async throws -> HistorySnapshot {
        let stale = value
        await waitForMigration()
        return stale
    }

    func apply(_ change: HistoryChange) async throws -> HistorySnapshot {
        throw HistoryError.database("Unsupported test operation")
    }

    func update(_ body: @Sendable (inout HistorySnapshot) throws -> Void) async throws -> HistorySnapshot {
        await waitForMigration()
        try body(&value)
        return value
    }

    func replaceAll(_ snapshot: HistorySnapshot) async throws {
        value = snapshot
        release?.resume()
        release = nil
    }

    func current() -> HistorySnapshot { value }
}
