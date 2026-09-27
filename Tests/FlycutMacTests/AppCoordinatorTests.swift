import XCTest
import FlycutCore
import FlycutPlatform
@testable import FlycutMac

@MainActor final class AppCoordinatorTests: XCTestCase {
    func testApplyingOrdinarySettingReplacesPreviousPaletteFeedback() async throws {
        let domain = "flycut.synthetic.feedback." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var initial = FlycutSettings(); initial.saveMode = .never
        SettingsStore(defaults: defaults).save(initial)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", defaultsFactory: { _ in defaults }, repository: working)
        app.model.message = "Copied."
        var draft = app.settings; draft.stickyPalette.toggle()

        let result = try await app.applySettings(draft)
        XCTAssertEqual(result, "Changes applied.")
        XCTAssertEqual(app.settings.stickyPalette, draft.stickyPalette)
    }

    func testApplyingLoginSettingReportsCurrentApprovalAndFailureAfterPreviousPaletteFeedback() async throws {
        let cases: [(LoginItemStatus, String, Bool)] = [
            (.requiresApproval, "Approve Flycut in Login Items Settings.", true),
            (.error("Synthetic failure"), "Login item change failed. Check Login Items Settings.", false),
        ]
        for (status, expected, expectedEnabled) in cases {
            let domain = "flycut.synthetic.login-feedback." + UUID().uuidString
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            var initial = FlycutSettings(); initial.saveMode = .never
            SettingsStore(defaults: defaults).save(initial)
            let working = try SQLiteHistoryRepository(inMemory: ())
            let login = LoginItemService(client: LoginItemClient(status: { status }, register: {}, unregister: {}))
            let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", defaultsFactory: { _ in defaults }, repository: working, login: login)
            app.model.message = "Copied."
            var draft = app.settings; draft.openAtLogin = true

            let result = try await app.applySettings(draft)
            XCTAssertEqual(result, expected)
            XCTAssertEqual(app.settings.openAtLogin, expectedEnabled)
        }
    }

    func testProductionShapedStartupAndImportLeaveLegacySourceBytesUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "flycut.synthetic.settings." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let source = LegacySourceDiscovery.candidates(home: directory)[0]
        try FileManager.default.createDirectory(at: source.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["savePreference": 0, "store": ["version": "0.7", "jcList": [["Contents": "Synthetic legacy", "Type": "text", "Position": 0]], "favoritesList": []]], format: .xml, options: 0)
        try bytes.write(to: source.url)
        let working = try SQLiteHistoryRepository(inMemory: ())
        var requestedDomains: [String] = []
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut", storageDirectory: directory.appendingPathComponent("new-data"), defaultsFactory: { requestedDomains.append($0); return defaults }, repository: working, confirmRecovery: { _, _ in true })
        app.configure(app.settings) // The same startup settings application used before discovery.
        let migration = MigrationCoordinator(destination: working, backupDirectory: directory.appendingPathComponent("backups"), memoryDestination: working)
        let result = try await migration.import(source: source, choice: .importNew)
        app.configure(result.settingsForAdoption(preserving: app.settings))
        defaults.synchronize()
        XCTAssertEqual(requestedDomains, ["com.edynamics.flycut.settings.v3"])
        XCTAssertEqual(try Data(contentsOf: source.url), bytes)
        XCTAssertEqual(SettingsStore(defaults: defaults).load().saveMode, .never)
        XCTAssertEqual(AppCoordinator.settingsDomain(for: "com.edynamics.flycut.preview"), "com.edynamics.flycut.preview.settings.v3")
        XCTAssertEqual(AppCoordinator.settingsDomain(for: nil), "com.edynamics.flycut.preview.settings.v3")
    }

    func testApplyingSaveModeKeepsRecoveredCapacityThroughNextCapture() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "flycut.synthetic.recovery." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let disk = try SQLiteHistoryRepository(url: directory.appendingPathComponent("history.sqlite"))
        let saved = HistorySnapshot(recent: (0..<100).map { clip($0) }, favorites: (100..<160).map { clip($0, collection: .favorite) })
        try await disk.replaceAll(saved)
        var initial = FlycutSettings(); initial.saveMode = .never
        SettingsStore(defaults: defaults).save(initial)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", storageDirectory: directory, defaultsFactory: { _ in defaults }, repository: working, confirmRecovery: { current, saved in
            XCTAssertEqual(current.recent.count, 0); XCTAssertEqual(saved.recent.count, 100); return true
        })
        var draft = app.settings; draft.saveMode = .onQuit
        _ = try await app.applySettings(draft)
        XCTAssertEqual(app.settings.recentCapacity, 100)
        XCTAssertEqual(app.settings.favoriteCapacity, 60)
        let next = try await app.history.capture(clip(200))
        XCTAssertEqual(next.recent.count, 100)
        XCTAssertEqual(next.favorites.count, 60)
        // A later, separate capacity edit remains an explicit user choice.
        var reduced = app.settings; reduced.recentCapacity = 50
        _ = try await app.applySettings(reduced)
        XCTAssertEqual(app.settings.recentCapacity, 50)
    }

    func testSyncedHistoryRaisesCapacityBeforeNextCapture() async throws {
        let domain = "flycut.synthetic.synced-capacity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var initial = FlycutSettings(); initial.saveMode = .never
        SettingsStore(defaults: defaults).save(initial)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut.preview", defaultsFactory: { _ in defaults }, repository: working)
        let synced = HistorySnapshot(recent: (0..<51).map { clip($0) }, favorites: [])

        try await app.acceptSyncedHistory(synced)
        let next = try await app.history.capture(clip(100))

        XCTAssertEqual(app.settings.recentCapacity, 51)
        XCTAssertEqual(SettingsStore(defaults: defaults).load().recentCapacity, 51)
        XCTAssertEqual(next.recent.count, 51)
        XCTAssertEqual(Set(next.recent.dropFirst().map(\.id)), Set(synced.recent.dropLast().map(\.id)))
    }

    func testNeverOnboardingReadsDurableMarkerWithoutRestoringClips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "flycut.synthetic.marker." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let disk = try SQLiteHistoryRepository(url: directory.appendingPathComponent("history.sqlite"))
        try await disk.replaceAll(HistorySnapshot(recent: [clip(1)], favorites: [], migration: MigrationMarker(sourceIdentity: "synthetic", importedAt: Date())))
        var initial = FlycutSettings(); initial.saveMode = .never
        SettingsStore(defaults: defaults).save(initial)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut", storageDirectory: directory, defaultsFactory: { _ in defaults }, repository: working, confirmRecovery: { _, _ in XCTFail("Marker check must not recover history"); return false })
        let offer = try await app.shouldOfferMigration()
        XCTAssertFalse(offer)
        let memory = try await working.snapshot()
        XCTAssertTrue(memory.recent.isEmpty); XCTAssertNil(memory.migration)
        XCTAssertEqual(app.settings.saveMode, .never)
    }

    func testFreshInstallationSkipsImportUntilReadableLegacySourceExists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = directory.appendingPathComponent("fresh-home")
        let domain = "flycut.synthetic.fresh-import." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let working = try SQLiteHistoryRepository(inMemory: ())
        let app = AppCoordinator(bundleIdentifier: "com.edynamics.flycut", storageDirectory: directory.appendingPathComponent("app-data"),
                                 legacyHomeDirectory: home, defaultsFactory: { _ in defaults }, repository: working)

        let withoutSource = try await app.shouldOfferMigration()
        XCTAssertFalse(withoutSource)
        let source = LegacySourceDiscovery.candidates(home: home)[0].url
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic readable source".utf8).write(to: source)
        let withSource = try await app.shouldOfferMigration()
        XCTAssertTrue(withSource)
    }
    private func clip(_ index: Int, collection: CollectionKind = .recent) -> Clip {
        Clip(id: UUID(), text: "Synthetic \(index)", pasteboardType: "text", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: collection, order: index)
    }
}
