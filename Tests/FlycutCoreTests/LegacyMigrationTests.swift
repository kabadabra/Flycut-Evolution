import Foundation
import XCTest
import SQLite3
@testable import FlycutCore

final class LegacyMigrationTests: XCTestCase, @unchecked Sendable {
    func fixture(_ recent: [Any], favorites: [Any] = [], save: Int = 1) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["savePreference": save, "store": ["version": "0.7", "rememberNum": 1, "favoritesRememberNum": 1, "jcList": recent, "favoritesList": favorites]], format: .xml, options: 0)
    }
    var record: [String: Any] { ["Contents": " e\u{301} 🦊\n\tline\r\n", "Type": "NSStringPboardType", "Position": 999, "Timestamp": 0, "AppLocalizedName": "Synthetic", "AppBundleURL": "file:///Synthetic.app"] }
    func testChangedPreviewSourceAndDestinationRequireNewConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = LegacySource(url: directory.appendingPathComponent("source.plist"))
        try fixture([record]).write(to: source.url)
        let destination = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: destination, backupDirectory: directory.appendingPathComponent("backup"))
        let preview = try await coordinator.preview(source: source)
        try fixture([record, record]).write(to: source.url)
        do { _ = try await coordinator.import(source: source, choice: .importNew, expectedSourceFingerprint: preview.sourceFingerprint); XCTFail("Changed source must be reviewed") }
        catch { XCTAssertEqual(error as? MigrationError, .previewChanged) }
        let fresh = try await coordinator.preview(source: source)
        try await destination.replaceAll(LegacyStoreParser.parse(data: fixture([record])).history)
        do { _ = try await coordinator.import(source: source, choice: .merge(confirmed: true), expectedDestinationFingerprint: fresh.destinationFingerprint); XCTFail("Changed destination must be reviewed") }
        catch { XCTAssertEqual(error as? MigrationError, .previewChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("backup").path))
    }
    func testExactLegacyShapeOrderDuplicatesMetadataAndCapacity() throws {
        var second = record; second["Type"] = "public.utf8-plain-text"; second["Timestamp"] = 4_294_967_296 as Int64
        let data = try fixture([record, second], favorites: [second, record])
        let result = try LegacyStoreParser.parse(data: data)
        XCTAssertEqual(result.history.recent.map(\.pasteboardType), ["NSStringPboardType", "public.utf8-plain-text"])
        XCTAssertEqual(Array(result.history.recent[0].text.utf8), Array((record["Contents"] as! String).utf8))
        XCTAssertEqual(result.history.recent[0].capturedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(result.history.recent[1].capturedAt, Date(timeIntervalSince1970: 4_294_967_296))
        XCTAssertEqual(result.history.favorites[0].sourceBundleURL, "file:///Synthetic.app")
        XCTAssertEqual(result.settings.recentCapacity, 2)
        XCTAssertEqual(result.settings.favoriteCapacity, 2)
        XCTAssertNotEqual(result.history.recent[0].id, result.history.favorites[1].id)
    }
    func testMalformedAndUnsupportedAreReportedWithoutContent() throws {
        let result = try LegacyStoreParser.parse(data: fixture([record, "bad", ["Contents": "secret"], ["Contents": "minimal", "Type": "text"]]))
        XCTAssertEqual(result.history.recent.count, 2)
        XCTAssertEqual(result.skipped.count, 2)
        XCTAssertNil(result.history.recent[1].capturedAt)
        XCTAssertFalse(result.warnings.joined().contains("secret"))
        XCTAssertThrowsError(try LegacyStoreParser.parse(data: PropertyListSerialization.data(fromPropertyList: [:], format: .xml, options: 0)))
    }
    func testOversizedListsAreNeverTrimmed() throws {
        let result = try LegacyStoreParser.parse(data: fixture(Array(repeating: record, count: 501)))
        XCTAssertEqual(result.history.recent.count, 501)
        XCTAssertEqual(result.settings.recentCapacity, 501)
    }
    func testImportBackupsIdempotencyAndSaveNever() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist")
        let data = try fixture([record]); try data.write(to: url)
        let destination = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: destination, backupDirectory: directory.appendingPathComponent("backups"))
        let source = LegacySource(url: url)
        let report = try await coordinator.import(source: source, choice: .importNew)
        XCTAssertEqual(report.importedCount, 1)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(try Data(contentsOf: report.sourceBackup!), data)
        let again = try await coordinator.import(source: source, choice: .importNew)
        XCTAssertTrue(again.alreadyImported)
        let snapshot = try await destination.snapshot(); XCTAssertEqual(snapshot.recent.count, 1)
        try fixture([record], save: 0).write(to: url)
        let privateSource = LegacySource(url: url)
        let privateReport = try await coordinator.import(source: privateSource, choice: .importNew)
        XCTAssertTrue(privateReport.inMemoryOnly)
        let persistentSnapshot = try await destination.snapshot(); XCTAssertEqual(persistentSnapshot.migration?.sourceIdentity, source.identity)
        let active = await coordinator.activeRepository
        let memory = try await active.snapshot(); XCTAssertEqual(memory.migration?.sourceIdentity, privateSource.identity)
    }
    func testNonemptyRequiresConfirmationAndBacksUpExactDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"); try fixture([record]).write(to: url)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let original = try LegacyStoreParser.parse(data: fixture([record])).history
        try await repository.replaceAll(original)
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        let source = LegacySource(url: url)
        do { _ = try await coordinator.import(source: source, choice: .importNew); XCTFail("Must require a destination choice") } catch { XCTAssertEqual(error as? MigrationError, .confirmationRequired) }
        let result = try await coordinator.import(source: source, choice: .merge(confirmed: true))
        let backup = try JSONDecoder().decode(HistorySnapshot.self, from: Data(contentsOf: result.destinationBackup!))
        XCTAssertEqual(backup, original)
        let final = try await repository.snapshot(); XCTAssertEqual(final.recent.count, 2)
        XCTAssertEqual(result.settings.recentCapacity, 2)
    }
    func testDiscoveryOffersAllDomainsAndPicker() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for source in LegacySourceDiscovery.candidates(home: directory) {
            try FileManager.default.createDirectory(at: source.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fixture([record]).write(to: source.url)
        }
        let result = LegacySourceDiscovery.discover(home: directory)
        XCTAssertEqual(result.sources.count, 3)
        XCTAssertTrue(result.offersFilePicker)
    }
    func testCheckedInFixtureUnsupportedSettingsAndPrivacyPermissions() async throws {
        let fixtureURL = Bundle.module.url(forResource: "legacy-0.7", withExtension: "plist", subdirectory: "Fixtures")!
        let parsed = try LegacyStoreParser.parse(data: Data(contentsOf: fixtureURL))
        XCTAssertEqual(parsed.history.recent.count, 2)
        XCTAssertTrue(parsed.warnings.contains { $0.contains("iCloud") })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory)
        let report = try await coordinator.import(source: LegacySource(url: fixtureURL), choice: .importNew)
        let permissions = try FileManager.default.attributesOfItem(atPath: report.sourceBackup!.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
    }

    func testSaveNeverPreviewAndImportDoNotCreateBackupFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"); try fixture([record], save: 0).write(to: url)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        try await repository.replaceAll(LegacyStoreParser.parse(data: fixture([record])).history)
        let backups = directory.appendingPathComponent("backup")
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: backups)
        let source = LegacySource(url: url)
        let preview = try await coordinator.preview(source: source)
        XCTAssertEqual(preview.destinationCount, 0)
        let report = try await coordinator.import(source: source, choice: .importNew)
        XCTAssertNil(report.sourceBackup)
        XCTAssertNil(report.destinationBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        let persistent = try await coordinator.import(source: source, choice: .replace(confirmed: true), persistentSaveMode: .onQuit)
        XCTAssertFalse(persistent.inMemoryOnly)
        XCTAssertNotNil(persistent.sourceBackup)
        XCTAssertNotNil(persistent.destinationBackup)
    }

    func testEmptyImportAbortsAndDifferentSourcesRemainIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"); try fixture([]).write(to: url)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        do { _ = try await coordinator.import(source: LegacySource(url: url), choice: .importNew); XCTFail("Empty import must abort") }
        catch { XCTAssertEqual(error as? MigrationError, .nothingImportable) }
        try fixture([record]).write(to: url)
        let bURL = directory.appendingPathComponent("b.plist")
        try fixture([record]).write(to: bURL)
        let a = LegacySource(url: url), b = LegacySource(url: bURL)
        _ = try await coordinator.import(source: a, choice: .importNew)
        _ = try await coordinator.import(source: b, choice: .merge(confirmed: true))
        let rerun = try await coordinator.import(source: a, choice: .merge(confirmed: true))
        XCTAssertTrue(rerun.alreadyImported)
        let history = try await repository.snapshot(); XCTAssertEqual(history.recent.count, 2)
        let cURL = directory.appendingPathComponent("c.plist")
        try fixture([record]).write(to: cURL)
        let replaceSource = LegacySource(url: cURL)
        let replaced = try await coordinator.import(source: replaceSource, choice: .replace(confirmed: true))
        XCTAssertNotNil(replaced.destinationBackup)
        let afterReplace = try await repository.snapshot(); XCTAssertEqual(afterReplace.recent.count, 1)
    }

    func testDestinationTransactionFailureRollsBackClipsAndMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"); try fixture([record]).write(to: url)
        let database = directory.appendingPathComponent("history.sqlite")
        let baseline = try SQLiteHistoryRepository(url: database)
        let original = try LegacyStoreParser.parse(data: fixture([record])).history
        try await baseline.replaceAll(original)
        let failing = try SQLiteHistoryRepository(url: database, permissionMaintenance: { _ in throw MigrationError.invalidPropertyList }, metadataStep: sqlite3_step)
        let coordinator = MigrationCoordinator(destination: failing, backupDirectory: directory.appendingPathComponent("backup"))
        do { _ = try await coordinator.import(source: LegacySource(url: url), choice: .replace(confirmed: true)); XCTFail("Injected commit failure must propagate") }
        catch { XCTAssertEqual(error as? MigrationError, .invalidPropertyList) }
        let after = try await baseline.snapshot()
        XCTAssertEqual(after, original)
    }

    func testBackupFailureLeavesDestinationAndSourceUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"), data = try fixture([record])
        try data.write(to: url)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: url)
        do { _ = try await coordinator.import(source: LegacySource(url: url), choice: .importNew); XCTFail("Backup failure must abort") } catch {}
        let after = try await repository.snapshot()
        XCTAssertTrue(after.recent.isEmpty)
        XCTAssertNil(after.migration)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testPreviewShowsMergedCapacityBeforeConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.plist"); try fixture([record]).write(to: url)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        try await repository.replaceAll(LegacyStoreParser.parse(data: fixture([record, record])).history)
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        let report = try await coordinator.preview(source: LegacySource(url: url), choice: .merge(confirmed: false))
        XCTAssertEqual(report.settings.recentCapacity, 3)
    }

    func testRepeatedSourceKeepsRetainedHistoryCapacitiesInImportAndPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let aURL = directory.appendingPathComponent("a.plist"), bURL = directory.appendingPathComponent("b.plist")
        try fixture([record], favorites: [record]).write(to: aURL)
        try fixture([record], favorites: [record]).write(to: bURL)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        let a = LegacySource(url: aURL), b = LegacySource(url: bURL)
        _ = try await coordinator.import(source: a, choice: .importNew)
        _ = try await coordinator.import(source: b, choice: .merge(confirmed: true))
        let repeated = try await coordinator.import(source: a, choice: .importNew)
        let preview = try await coordinator.preview(source: a, choice: .merge(confirmed: false))
        XCTAssertTrue(repeated.alreadyImported)
        XCTAssertTrue(preview.alreadyImported)
        XCTAssertEqual(repeated.settings.recentCapacity, 2)
        XCTAssertEqual(repeated.settings.favoriteCapacity, 2)
        XCTAssertEqual(preview.settings.recentCapacity, 2)
        XCTAssertEqual(preview.settings.favoriteCapacity, 2)
        var currentSettings = FlycutSettings()
        currentSettings.recentCapacity = 3
        currentSettings.favoriteCapacity = 3
        currentSettings.menuIcon = 2
        currentSettings.saveMode = .afterEachClip
        let adopted = repeated.settingsForAdoption(preserving: currentSettings)
        XCTAssertEqual(adopted, currentSettings)
        var undersized = currentSettings
        undersized.recentCapacity = 1
        undersized.favoriteCapacity = 1
        let repaired = preview.settingsForAdoption(preserving: undersized)
        XCTAssertEqual(repaired.recentCapacity, 2)
        XCTAssertEqual(repaired.favoriteCapacity, 2)
        XCTAssertEqual(repaired.menuIcon, 2)
        let beforeCapture = try await repository.snapshot()
        let service = HistoryService(repository: repository, recentCapacity: adopted.recentCapacity, favoriteCapacity: adopted.favoriteCapacity)
        let newClip = Clip(id: UUID(), text: "Synthetic subsequent capture", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
        let captured = try await service.capture(newClip)
        XCTAssertEqual(captured.recent.count, 3)
        XCTAssertTrue(Set(beforeCapture.recent.map(\.id)).isSubset(of: Set(captured.recent.map(\.id))))
        let favorited = try await service.favorite(id: newClip.id)
        XCTAssertEqual(favorited.favorites.count, 3)
        XCTAssertTrue(Set(beforeCapture.favorites.map(\.id)).isSubset(of: Set(favorited.favorites.map(\.id))))
    }

    func testDiscoveredAndPickedSourceIncludingSymlinkAreOneImport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidate = LegacySourceDiscovery.candidates(home: directory)[0]
        try FileManager.default.createDirectory(at: candidate.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture([record]).write(to: candidate.url)
        let discovered = try XCTUnwrap(LegacySourceDiscovery.discover(home: directory).sources.first)
        let picked = LegacySource(url: discovered.url)
        let alias = directory.appendingPathComponent("alias.plist")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: discovered.url)
        let pickedAlias = LegacySource(url: alias)
        XCTAssertEqual(discovered.identity, picked.identity)
        XCTAssertEqual(picked.identity, pickedAlias.identity)
        let repository = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
        _ = try await coordinator.import(source: discovered, choice: .importNew)
        let rerun = try await coordinator.import(source: picked, choice: .merge(confirmed: true))
        let aliasRerun = try await coordinator.import(source: pickedAlias, choice: .merge(confirmed: true))
        XCTAssertTrue(rerun.alreadyImported)
        XCTAssertTrue(aliasRerun.alreadyImported)
        let history = try await repository.snapshot()
        XCTAssertEqual(history.recent.count, 1)
    }

    func testLegacyDomainAndPathAliasMarkersPreventReimport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = LegacySourceDiscovery.candidates(home: directory)[0]
        try FileManager.default.createDirectory(at: source.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try fixture([record]); try data.write(to: source.url)
        let alias = directory.appendingPathComponent("alias.plist")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source.url)
        for oldIdentity in ["com.edynamics.flycut", alias.standardizedFileURL.path] {
            let repository = try SQLiteHistoryRepository(inMemory: ())
            var existing = try LegacyStoreParser.parse(data: data).history
            existing.migration = MigrationMarker(sourceIdentity: oldIdentity, importedAt: Date(timeIntervalSince1970: 1))
            try await repository.replaceAll(existing)
            let coordinator = MigrationCoordinator(destination: repository, backupDirectory: directory.appendingPathComponent("backup"))
            let result = try await coordinator.import(source: LegacySource(url: source.url), choice: .importNew)
            XCTAssertTrue(result.alreadyImported)
            let after = try await repository.snapshot()
            XCTAssertEqual(after, existing)
        }
    }

}
