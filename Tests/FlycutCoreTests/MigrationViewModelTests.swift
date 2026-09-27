import XCTest
@testable import FlycutCore

final class MigrationViewModelTests: XCTestCase, @unchecked Sendable {
    func testDisposableProfileImportMemoryChoiceAndRetryWithoutSourceMutation() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = LegacySourceDiscovery.candidates(home: home)[0]
        try FileManager.default.createDirectory(at: source.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["savePreference": 0, "removeDuplicates": true,
            "store": ["version": "0.7", "jcList": [["Contents": "Synthetic profile", "Type": "text", "Position": 0]], "favoritesList": [["Contents": "Synthetic favorite", "Type": "text", "Position": 0]]]], format: .xml, options: 0)
        try bytes.write(to: source.url)
        let discovery = LegacySourceDiscovery.discover(home: home)
        XCTAssertEqual(discovery.sources.count, 1)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let coordinator = MigrationCoordinator(destination: working, backupDirectory: home.appendingPathComponent("backups"), memoryDestination: working)
        var decision = MigrationViewModel(sources: discovery.sources)
        decision.select(source)
        let preview = try await coordinator.preview(source: source, destination: working)
        decision.acceptPreview(destinationCount: preview.destinationCount, inMemoryOnly: preview.inMemoryOnly, importableCount: preview.recentCount + preview.favoriteCount)
        decision.storage = .memory; decision.confirmed = true
        decision.cancel()
        var snapshot = try await working.snapshot()
        XCTAssertTrue(snapshot.recent.isEmpty)
        try Data("invalid synthetic plist".utf8).write(to: source.url)
        do { _ = try await coordinator.import(source: source, choice: .importNew); XCTFail("Invalid source must fail") } catch { }
        try bytes.write(to: source.url)
        let result = try await coordinator.import(source: source, choice: .importNew)
        snapshot = try await working.snapshot()
        XCTAssertEqual(snapshot.recent.count, 1); XCTAssertEqual(snapshot.favorites.count, 1)
        XCTAssertTrue(result.inMemoryOnly)
        XCTAssertEqual(try Data(contentsOf: source.url), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("backups").path))
        let other = source.url.deletingLastPathComponent().appendingPathComponent("other.plist")
        try bytes.write(to: other)
        do { _ = try await coordinator.import(source: LegacySource(url: other), choice: .importNew); XCTFail("Memory destination requires explicit conflict resolution") } catch { XCTAssertEqual(error as? MigrationError, .confirmationRequired) }
        snapshot = try await working.snapshot(); XCTAssertEqual(snapshot.recent.count, 1)
    }
    func testSourcesRequireSelectionAndConfirmation() {
        let sources = [LegacySource(url: URL(fileURLWithPath: "/synthetic/a.plist")), LegacySource(url: URL(fileURLWithPath: "/synthetic/b.plist"))]
        var model = MigrationViewModel(sources: sources)
        XCTAssertNil(model.selectedSource)
        XCTAssertFalse(model.canImport)
        model.select(sources[1])
        model.acceptPreview(destinationCount: 3, inMemoryOnly: false, importableCount: 2)
        model.confirmed = true
        XCTAssertFalse(model.canImport)
        model.action = .merge
        XCTAssertTrue(model.canImport)
        model.select(sources[0])
        XCTAssertFalse(model.canImport)
        XCTAssertFalse(model.confirmed)
    }
    func testSaveNeverRequiresExplicitMemoryOrPersistentChoice() {
        var model = MigrationViewModel(sources: [])
        model.select(LegacySource(url: URL(fileURLWithPath: "/synthetic/a.plist")))
        model.acceptPreview(destinationCount: 0, inMemoryOnly: true, importableCount: 2)
        model.confirmed = true
        XCTAssertFalse(model.canImport)
        model.storage = .memory
        XCTAssertTrue(model.canImport)
        XCTAssertNil(model.persistentSaveMode)
        model.storage = .afterEachClip
        XCTAssertEqual(model.persistentSaveMode, .afterEachClip)
    }
    func testCancelAndFailedRetryRequireFreshConfirmation() {
        var model = MigrationViewModel(sources: [])
        model.select(LegacySource(url: URL(fileURLWithPath: "/synthetic/a.plist")))
        model.acceptPreview(destinationCount: 0, inMemoryOnly: false, importableCount: 1)
        model.confirmed = true
        XCTAssertTrue(model.beginImport())
        XCTAssertFalse(model.canImport)
        model.failed()
        XCTAssertFalse(model.canImport)
        model.confirmed = true
        XCTAssertTrue(model.beginImport())
        model.cancel()
        XCTAssertNil(model.selectedSource)
        XCTAssertFalse(model.canImport)
    }
    func testFailedPreviewRefreshCannotReuseOldConfirmation() {
        var model = MigrationViewModel(sources: [])
        model.select(LegacySource(url: URL(fileURLWithPath: "/synthetic/a.plist")))
        model.acceptPreview(destinationCount: 0, inMemoryOnly: false, importableCount: 1)
        model.confirmed = true
        XCTAssertTrue(model.canImport)
        model.invalidatePreview()
        model.confirmed = true
        XCTAssertFalse(model.canImport)
    }
    func testPreviewIdentityCannotEnableProductionOnboarding() {
        XCTAssertFalse(MigrationViewModel.shouldOfferOnboarding(bundleIdentifier: "com.edynamics.flycut.preview", hasMarker: false))
        XCTAssertTrue(MigrationViewModel.shouldOfferOnboarding(bundleIdentifier: "com.edynamics.flycut", hasMarker: false))
        XCTAssertFalse(MigrationViewModel.shouldOfferOnboarding(bundleIdentifier: "com.edynamics.flycut", hasMarker: true))
    }
}
