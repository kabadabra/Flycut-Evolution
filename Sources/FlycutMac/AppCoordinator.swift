import AppKit
import OSLog
import SwiftUI
import Combine
import FlycutCore
import FlycutPlatform

@MainActor final class AppCoordinator: NSObject, NSApplicationDelegate {
    let model = PaletteModel()
    private(set) var settings: FlycutSettings
    private let settingsStore: SettingsStore
    private let repository: SQLiteHistoryRepository
    private var persistence: HistoryPersistence?
    private(set) var history: HistoryService
    private let wasEstablishedInstallation: Bool
    private var setupWindow: NSWindow?
    private var updaterSubscription: AnyCancellable?
    private var updater: UpdateService?
    private var recognition: ImageRecognitionCoordinator?
    private var monitor: ClipboardMonitor!
    private var hotkey: HotkeyService!
    private var historyHotkey: HotkeyService!
    private var paste: PasteService!
    private var shell: MenuBarController!
    private var pasteTargets = PasteTargetHistory(ownProcessID: ProcessInfo.processInfo.processIdentifier)
    private var activationObserver: NSObjectProtocol?
    private var pasteTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    private var cloudSync: CloudSyncController?
    private var cloudStatus: CloudSyncStatus = .off
    private var snapshot = HistorySnapshot(recent: [], favorites: [])
    private var registeredHotkey: FlycutHotkey?
    private var registeredHistoryHotkey: FlycutHotkey?
    private let accessibility = AccessibilityService()
    private var terminating = false
    private let login: LoginItemService
    private var settingsWindow: NSWindow?
    private var importWindow: NSWindow?
    private var settingsEditor: SettingsModel?
    private var migration: MigrationCoordinator?
    private var sessionStartedNever = false
    private let bundleIdentity: String
    private let storageDirectory: URL?
    private let legacyHomeDirectory: URL
    private let confirmRecovery: @MainActor (HistorySnapshot, HistorySnapshot) -> Bool
    /// Shared settings entry point.
    var showSettings: (() -> Void)?

    override convenience init() { self.init(bundleIdentifier: Bundle.main.bundleIdentifier) }

    static func settingsDomain(for bundleIdentifier: String?) -> String {
        (bundleIdentifier ?? "com.edynamics.flycut.preview") + ".settings.v3"
    }

    init(bundleIdentifier: String?, storageDirectory: URL? = nil,
         legacyHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         defaultsFactory: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) },
         repository: SQLiteHistoryRepository? = nil,
         login: LoginItemService = LoginItemService(),
         confirmRecovery: @escaping @MainActor (HistorySnapshot, HistorySnapshot) -> Bool = AppCoordinator.askToRecover) {
        bundleIdentity = bundleIdentifier ?? "com.edynamics.flycut.preview"
        self.storageDirectory = storageDirectory
        self.legacyHomeDirectory = legacyHomeDirectory
        self.confirmRecovery = confirmRecovery
        self.login = login
        // Never write v3 settings into the legacy source preferences domain.
        guard let defaults = defaultsFactory(Self.settingsDomain(for: bundleIdentifier)) else {
            fatalError("Unable to initialize isolated settings storage")
        }
        settingsStore = SettingsStore(defaults: defaults)
        let existingDirectory = storageDirectory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?.appendingPathComponent(bundleIdentity)
        wasEstablishedInstallation = settingsStore.isEstablishedInstallation || existingDirectory.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("history.sqlite").path) } == true
        settings = settingsStore.load()
        do { self.repository = try repository ?? SQLiteHistoryRepository() }
        catch { fatalError("Unable to initialize private history storage") }
        history = HistoryService(repository: self.repository, recentCapacity: settings.recentCapacity, favoriteCapacity: settings.favoriteCapacity)
        super.init()
    }
    private static func askToRecover(_ current: HistorySnapshot, _ saved: HistorySnapshot) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Load previously saved history?"
        alert.informativeText = "Saved history contains \(saved.recent.count) recent and \(saved.favorites.count) favorite clippings. Loading it replaces this session's \(current.recent.count + current.favorites.count) in-memory clippings. Export any session clippings you need before continuing. Cancel keeps saving disabled."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Load Saved History")
        return alert.runModal() == .alertSecondButtonReturn
    }
    isolated deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Observe before any Flycut activation. Clicking a persistent panel does
        // not invoke willPresent, but app B's preceding activation is still kept.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.pasteTargets.observeActivation(processID: processID) }
        }
        pasteTargets.observeActivation(processID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        updater = UpdateService()
        updater?.configure(automaticChecks: settings.automaticUpdateChecks)
        updater?.start()
        updaterSubscription = updater?.$message.sink { [weak self] message in
            if let message { self?.model.message = message; self?.settingsEditor?.message = message }
        }
        monitor = ClipboardMonitor(settings: { [weak self] in self?.settings ?? FlycutSettings() },
                                   onClip: { [weak self] clip in
            self?.enqueue { coordinator in
                _ = try await coordinator.history.capture(clip)
            }
        }, onAccessDenied: { [weak self] in self?.model.message = "Clipboard access was denied. Check macOS Privacy settings." })
        monitor.onImage = { [weak self] clip, asset in
            guard let self else { return }
            let task = enqueue { owner in
                _ = try await owner.history.captureImage(asset, clip: clip, budgetBytes: owner.settings.imageStorageLimitMiB * 1024 * 1024)
            }
            Task { [weak self] in await task.value; self?.recognition?.enqueue(clip) }
        }
        monitor.onImageRejected = { [weak self] in self?.model.message = "Image was not captured: invalid image, over 16 MiB, or over 24 million pixels." }
        monitor.onStateChange = { [weak self] state in
            guard let self else { return }
            recognition?.setPaused(state.isPaused)
            model.captureState = state; model.isPaused = state.isPaused
            settings.capturePaused = state.pause == .manual
            settingsStore.save(settings)
        }
        model.images = ImagePreviewModel(read: { [repository] hash in try await repository.imageData(for: hash) })
        recognition = ImageRecognitionCoordinator(read: { [repository] hash in try await repository.imageData(for: hash) }, eligible: { [weak self] clip in
            guard let self else { return false }
            return settings.imageRecognitionEnabled && model.selection.allClips.contains(where: { $0.id == clip.id && $0.image?.assetHash == clip.image?.assetHash }) && !settings.excludedApplications.contains(where: { $0.bundleIdentifier == clip.sourceBundleIdentifier })
        }, apply: { [weak self] id, hash, text, state in
            guard let self else { return }
            let task = enqueue { owner in
                guard owner.settings.imageRecognitionEnabled,
                      let clip = owner.model.selection.allClips.first(where: { $0.id == id }),
                      !owner.settings.excludedApplications.contains(where: { $0.bundleIdentifier == clip.sourceBundleIdentifier }) else { return }
                _ = try await owner.history.updateRecognition(id: id, assetHash: hash, text: text, state: state)
            }
            await task.value
        })
        paste = PasteService { [weak self] count in self?.monitor.recordSelfWrite(changeCount: count) }
        shell = MenuBarController(model: model)
        shell.willPresent = { [weak self] in self?.preparePresentation() }
        shell.didDismiss = { [weak self] in self?.pasteTask?.cancel(); self?.model.cancelPresentation() }
        hotkey = HotkeyService { [weak self] in self?.pasteCurrentClipboardAsPlainText() }
        historyHotkey = HotkeyService(client: CarbonHotkeyClient(identifier: 2)) { [weak self] in self?.shell.togglePalette() }
        model.isPaused = settings.rememberPause && settings.capturePaused
        monitor.isPaused = model.isPaused
        sessionStartedNever = settings.saveMode == .never
        showSettings = { [weak self] in self?.openSettings() }
        wireActions()
        configure(settings)
        // The monitor has already recorded the launch count without reading clipboard text.
        enqueue { coordinator in
            if coordinator.settings.saveMode != .never {
                do {
                    let directory = try coordinator.supportDirectory()
                    let disk = try SQLiteHistoryRepository(url: directory.appendingPathComponent("history.sqlite"))
                    let persistence = HistoryPersistence(destination: disk)
                    coordinator.persistence = persistence
                    try await persistence.restore(into: coordinator.repository)
                    _ = try await coordinator.history.normalizeRecents(backupTo: try coordinator.deduplicationBackupURL())
                    _ = try await coordinator.history.enforceCapacities(backupTo: coordinator.capacityBackupURL())
                } catch {
                    coordinator.model.storageWarning = "Saved history could not be loaded and has been left untouched. Capture will continue in memory only for this session. Export any new clippings before quitting; repair or restore the saved database before relaunching."
                }
            }
            if coordinator.settings.cloudSyncEnabled {
                do {
                    let cloud = try coordinator.makeCloudSync()
                    let current = try await coordinator.repository.snapshot()
                    let recovered = try await cloud.prepare(current, reauthorize: false)
                    try await coordinator.acceptSyncedHistory(recovered)
                    coordinator.cloudSync = cloud
                    try await cloud.activate()
                } catch CloudSyncError.accountChanged {
                    coordinator.settings.cloudSyncEnabled = false
                    coordinator.settingsStore.save(coordinator.settings)
                    coordinator.setCloudStatus(.accountChanged)
                } catch {
                    coordinator.setCloudStatus(.error("Cloud Sync could not start. Local history is available."))
                }
            }
            coordinator.monitor.start()
            let current = try await coordinator.repository.snapshot()
            coordinator.model.updateSnapshot(current)
            for clip in current.recent + current.favorites where clip.image?.recognitionState == .pending { coordinator.recognition?.enqueue(clip) }
            do {
                if try await coordinator.shouldOfferMigration() { coordinator.openImport(discover: true) }
                else if !coordinator.wasEstablishedInstallation && !coordinator.settingsStore.loadSetup().handled { coordinator.openSetup() }
            } catch {
                coordinator.model.storageWarning = "Previous migration status could not be read. Saved history was left untouched. Use Settings to retry saved history or review an explicit import."
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shell?.showPalette()
        return false
    }

    func configure(_ proposed: FlycutSettings) {
        var value = proposed; value.validate()
        let old = registeredHotkey
        if let hotkey, old != value.hotkey {
            do { try hotkey.register(value.hotkey); registeredHotkey = value.hotkey }
            catch {
                if let old, (try? hotkey.register(old)) != nil {
                    value.hotkey = old
                    model.message = "Shortcut unavailable. Your previous shortcut is still active."
                } else {
                    registeredHotkey = nil
                    model.message = "Global shortcut disabled because it could not be registered. Use the menu bar icon."
                }
            }
        }
        if let historyHotkey, registeredHistoryHotkey != value.historyHotkey {
            if value.historyHotkey == value.hotkey {
                value.historyHotkey = registeredHistoryHotkey ?? settings.historyHotkey
                model.message = "Choose different shortcuts for Open History and plain-text paste."
            } else {
                do { try historyHotkey.register(value.historyHotkey); registeredHistoryHotkey = value.historyHotkey }
                catch {
                    registeredHistoryHotkey = historyHotkey.currentShortcut
                    if let previous = registeredHistoryHotkey { value.historyHotkey = previous }
                    model.message = registeredHistoryHotkey == nil ? "Open History shortcut unavailable. Choose another shortcut in Settings." : "Open History shortcut unavailable. Your previous shortcut is still active."
                }
            }
        }
        value.capturePaused = monitor?.captureState.pause == .manual
        if value.saveMode == .never { sessionStartedNever = true }
        let recognitionEnabledChanged = !settings.imageRecognitionEnabled && value.imageRecognitionEnabled
        let imageBudgetChanged = settings.imageStorageLimitMiB != value.imageStorageLimitMiB
        let imageSyncChanged = settings.imageSyncEnabled != value.imageSyncEnabled
        settings = value
        if imageSyncChanged { enqueue { owner in
            try await owner.cloudSync?.setImageSyncEnabled(owner.settings.imageSyncEnabled)
            try await owner.cloudSync?.recordLocal(owner.repository.snapshot())
        } }
        if imageBudgetChanged { enqueue { owner in
            if try await !owner.repository.trimImageBudget(to: owner.settings.imageStorageLimitMiB * 1024 * 1024, archive: owner.settings.saveForgottenClippings && owner.settings.saveMode != .never ? owner.settings.autoSaveToLocation.map(EvictionArchive.init) : nil) { owner.model.message = "Image favorites exceed the storage limit. Increase the limit or remove image favorites." }
        } }
        settingsStore.save(value)
        updater?.configure(automaticChecks: value.automaticUpdateChecks)
        model.apply(value)
        recognition?.setEnabled(value.imageRecognitionEnabled)
        if recognitionEnabledChanged { for clip in model.selection.allClips where clip.image?.recognitionState == .pending { recognition?.enqueue(clip) } }
        recognition?.invalidateDisallowedSources(Set(value.excludedApplications.map(\.bundleIdentifier)))
        history = HistoryService(repository: repository, recentCapacity: value.recentCapacity, favoriteCapacity: value.favoriteCapacity,
                                 archive: value.saveMode == .never ? nil : value.autoSaveToLocation.map(EvictionArchive.init),
                                 archiveRecents: value.saveForgottenClippings, archiveFavorites: value.saveForgottenFavorites)
        shell?.applyAppearance(value)
        NSApp?.appearance = value.appearance == "system" ? nil : NSAppearance(named: value.appearance == "dark" ? .darkAqua : .aqua)
    }
    private func wireActions() {
        model.perform = { [weak self] in self?.perform($0) }
        model.pause = { [weak self] in
            guard let self else { return }
            if monitor.isPaused { monitor.resumeCapture() } else { monitor.pause(for: nil) }
        }
        model.pauseFor = { [weak self] in self?.monitor.pause(for: $0) }
        model.ignoreNextCopy = { [weak self] in self?.monitor.ignoreNextCopy() }
        model.cancelIgnoreNextCopy = { [weak self] in self?.monitor.cancelIgnoreNextCopy() }
        model.clear = { [weak self] in self?.enqueue { _ = try await $0.history.clearRecents() } }
        model.settings = { [weak self] in
            guard let self else { return }
            showSettings?()
        }
        model.about = {
            NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Flycut Evolution", .applicationVersion: FlycutVersion.current,
                .credits: NSAttributedString(string: "Maintained by Emerging Dynamics\nFork of TermiT/Flycut and Jumpcut\nFree and open source · MIT license")])
            NSApp.activate(ignoringOtherApps: true)
        }
        model.accessibility = { [weak self] in self?.accessibility.openSettings() }
        model.saveFavorite = { [weak self] id, edit in
            guard let self else { throw HistoryError.database("App unavailable") }
            try await self.mutateFavorite { _ = try await $0.history.updateFavorite(id: id, edit: edit) }
        }
        model.moveFavorite = { [weak self] id, offset in
            guard let self else { throw HistoryError.database("App unavailable") }
            try await self.mutateFavorite { _ = try await $0.history.moveFavorite(id: id, offset: offset) }
        }
        model.copyExtractedText = { [weak self] id in
            guard let self, let text = model.selection.clip(id: id)?.image?.recognizedText, !text.isEmpty else { self?.model.message = "No recognized text is available yet."; return }
            Task { [weak self] in
                guard let self else { return }
                reportPasteResult(await paste.copyOrPaste(text, mode: .copy, previousApp: nil))
            }
        }
        model.retryRecognition = { [weak self] id in
            guard let self, let clip = model.selection.clip(id: id) else { return }
            guard settings.imageRecognitionEnabled else { model.message = "Enable local text recognition in Images settings."; return }
            recognition?.cancel(id: id); recognition?.enqueue(clip)
        }
        model.showSetup = { [weak self] in self?.openSetup() }
        model.checkForUpdates = { [weak self] in
            guard let self else { return }
            updater?.checkForUpdates()
            model.message = updater?.message
        }
        model.quit = { NSApp.terminate(nil) }
    }
    private func preparePresentation() {
        pasteTask?.cancel()
        pasteTargets.observeActivation(processID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        model.needsAccessibility = !accessibility.isTrusted
        model.preparePresentation()
    }
    private func perform(_ command: PaletteCommand) {
        switch command {
        case .next: model.selection.move(1)
        case .previous: model.selection.move(-1)
        case .digit(let value): model.selection.selectDigit(value)
        case .dismiss: shell.dismiss()
        case .activateID(let id):
            if let clip = model.selection.clip(id: id) { copyOrPaste(.paste, plain: false, explicitClip: clip) }
        case .activate: copyOrPaste(.paste, plain: false)
        case .activatePlain: copyOrPaste(.paste, plain: true)
        case .copyToTop(let id):
            model.selection.select(id)
            copyOrPaste(.copy, plain: false, forceMoveToTop: true)
        case .favorite:
            guard let clip = model.selection.selected, clip.collection == .recent else { return }
            Task {
                do { try await mutateFavorite { _ = try await $0.history.favorite(id: clip.id) } }
                catch { model.message = "Favorite could not be saved. Existing favorites are unchanged." }
            }
        case .switchCollection: model.selection.collection = model.selection.collection == .recent ? .favorite : .recent
        case .delete:
            guard let clip = model.selection.selected else { return }
            enqueue { _ = try await $0.history.delete(id: clip.id) }
        case .exportSelected: if let clip = model.selection.selected { export([clip]) }
        case .exportAll: export(model.selection.collection == .recent ? snapshot.recent : snapshot.favorites)
        }
    }
    private func copyOrPaste(_ mode: PasteMode, plain: Bool, forceMoveToTop: Bool = false, explicitClip: Clip? = nil) {
        guard let clip = explicitClip ?? model.selection.selected else { return }
        pasteTask?.cancel()
        pasteTargets.observeActivation(processID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let target = pasteTargets.previousExternalApp
        if mode == .paste {
            shell.prepareForPaste(sticky: settings.stickyPalette)
        } else if !settings.stickyPalette { shell.dismiss() }
        pasteTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let result: PasteResult
            if let image = clip.image, !plain {
                guard let png = try? await repository.imageData(for: image.assetHash), !Task.isCancelled else { model.message = "Image could not be loaded."; return }
                result = await paste.copyOrPasteImage(png, mode: mode, previousApp: target)
            } else { result = await paste.copyOrPaste(clip, plain: plain, mode: mode, previousApp: target) }
            guard !Task.isCancelled else { return }
            if result == .clipboardUnavailable, clip.files?.isEmpty == false, clip.image == nil {
                model.message = "File is no longer available at its original path. You can still copy its name or path from the preview."
                shell.showPalette()
            } else { reportPasteResult(result) }
            if clip.collection == .recent, (forceMoveToTop || settings.pasteMovesToTop), result != .writeFailed && result != .clipboardUnavailable {
                enqueue { _ = try await $0.history.moveToTop(id: clip.id) }
            }
        }
    }
    private func pasteCurrentClipboardAsPlainText() {
        let logger = Logger(subsystem: "com.edynamics.flycut", category: "PlainPaste")
        logger.notice("Shortcut received; trusted=\(self.accessibility.isTrusted) foreground=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)")
        pasteTask?.cancel()
        // Capture a just-copied rich item before a fallback replaces its formats.
        monitor.pollOnce()
        shell.dismiss(cancelPaste: false)
        pasteTargets.observeActivation(processID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let target = pasteTargets.previousExternalApp
        pasteTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let result = await paste.pasteCurrentClipboardAsPlainText(previousApp: target)
            logger.notice("Shortcut result=\(String(describing: result), privacy: .public) target=\(target ?? -1) cancelled=\(Task.isCancelled)")
            guard !Task.isCancelled else { return }
            reportPasteResult(result, showPanelOnFailure: false)
        }
    }
    private func reportPasteResult(_ result: PasteResult, showPanelOnFailure: Bool = true) {
        var failed = false
        switch result {
        case .copied: model.message = "Copied."
        case .pasted: model.message = nil
        case .copiedNeedsAccessibility:
            model.reportAccessibilityDenied()
            failed = true
        case .copiedNoEditableTarget:
            model.message = "Copied. No editable text field is focused."
            failed = true
        case .copiedPasteUnavailable:
            model.message = "Copied. Paste manually in the destination app."
            failed = true
        case .writeFailed:
            model.message = "Could not write to the clipboard."
            failed = true
        case .pasteNeedsAccessibility:
            model.message = "Allow Accessibility access to paste with the shortcut."
            model.needsAccessibility = true
            failed = true
        case .clipboardDenied:
            model.message = "Allow clipboard access to paste unformatted text."
            failed = true
        case .clipboardUnavailable:
            model.message = "The clipboard has no text to paste."
            failed = true
        case .clipboardChanged:
            model.message = "The clipboard changed. Try the shortcut again."
            failed = true
        case .pasteUnavailable:
            model.message = "Could not paste into the previous app."
            failed = true
        case .noEditableTarget:
            model.message = "No editable text field is focused."
            failed = true
        }
        if failed {
            if showPanelOnFailure { shell.showPalette() }
            else { shell.indicateShortcutFailure(model.message ?? "Could not paste.") }
        } else if !showPanelOnFailure { shell.clearShortcutFeedback() }
    }
    private func export(_ clips: [Clip]) {
        guard !clips.isEmpty else { return }
        Task {
            do {
                let assets = try await repository.exportAssets(for: .init(recent: clips, favorites: []))
                let value = try ClipExport.make(clips, assets: assets)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = value.filename
                panel.directoryURL = settings.saveToLocation
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try value.data.write(to: url, options: .atomic)
                model.message = "Export saved."
            } catch { model.message = "Unable to save the export. Choose another location." }
        }
    }
    /// Serialize capture and UI writes; shutdown waits for the same queue before persisting.
    @discardableResult
    private func enqueue(recordForSync: Bool = true,
                         _ operation: @escaping @MainActor (AppCoordinator) async throws -> Void) -> Task<Void, Never> {
        let previous = mutationTask
        mutationTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await operation(self)
                snapshot = try await repository.snapshot()
                model.updateSnapshot(snapshot)
                if settings.saveMode == .afterEachClip { try await persist(snapshot) }
                if recordForSync && settings.cloudSyncEnabled {
                    do { try await cloudSync?.recordLocal(snapshot) }
                    catch { setCloudStatus(.error("Cloud Sync could not save a change. Local history is safe.")) }
                }
            } catch {
                if case HistoryError.database(let detail) = error, (detail.hasPrefix("Image favorites") || detail.hasPrefix("Synced images")) { model.message = detail }
                else { model.message = "History could not be updated or saved. Check the automatic export folder and saved-history access, then try again." }
            }
        }
        return mutationTask!
    }
    private func mutateFavorite(_ operation: @escaping @MainActor (AppCoordinator) async throws -> Void) async throws {
        let previous = mutationTask
        let task = Task { @MainActor in
            await previous?.value
            let after = try await FavoriteMutation.perform(repository: repository, operation: {
                try await operation(self)
            }, persist: { value in
                if self.settings.saveMode == .afterEachClip { try await self.persist(value) }
            })
            snapshot = after; model.updateSnapshot(after)
            if settings.cloudSyncEnabled {
                do { try await cloudSync?.recordLocal(after) }
                catch { setCloudStatus(.error("Cloud Sync could not save a change. Local history is safe.")) }
            }
        }
        mutationTask = Task { _ = try? await task.value }
        try await task.value
    }
    private func persist(_ snapshot: HistorySnapshot, mode: SaveMode? = nil) async throws {
        guard (mode ?? settings.saveMode) != .never else { return }
        guard let persistence, try await persistence.save(snapshot, assets: repository.exportAssets(for: snapshot)) else {
            if model.storageWarning == nil {
                model.storageWarning = "This session is running in memory only. Saved history has not been replaced. Export new clippings before quitting."
            }
            throw HistoryError.database("Saved history is unavailable")
        }
    }

    private func supportDirectory() throws -> URL {
        if let storageDirectory { return storageDirectory }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(bundleIdentity, isDirectory: true)
    }

    private func setCloudStatus(_ status: CloudSyncStatus) {
        cloudStatus = status
        settingsEditor?.cloudStatus = status
    }

    /// Reject an oversized image collection without local evictions or remote tombstones.
    @discardableResult
    func acceptSyncedHistory(_ merged: HistorySnapshot, assets: [ImageAsset] = []) async throws -> HistorySnapshot {
        var retained = merged
        retained.recent = Array(merged.recent.prefix(settings.recentCapacity))
        retained.favorites = Array(merged.favorites.prefix(settings.favoriteCapacity))
        if retained != merged && settings.saveMode != .never {
            let existing = try await repository.exportAssets(for: repository.snapshot())
            let all = Dictionary((existing + assets).map { ($0.hash, $0) }, uniquingKeysWith: { _, incoming in incoming })
            let hashes = Set((merged.recent + merged.favorites).compactMap { $0.image?.assetHash })
            let backupAssets = hashes.compactMap { all[$0] }
            try await history.backupSnapshot(merged, assets: backupAssets, to: capacityBackupURL())
            let bytes = Dictionary(uniqueKeysWithValues: backupAssets.map { ($0.hash, $0.png) })
            if settings.saveMode != .never, let directory = settings.autoSaveToLocation {
                let archive = EvictionArchive(directory: directory)
                if settings.saveForgottenClippings { try archive.save(Array(merged.recent.dropFirst(settings.recentCapacity)), imageAssets: bytes) }
                if settings.saveForgottenFavorites { try archive.save(Array(merged.favorites.dropFirst(settings.favoriteCapacity)), imageAssets: bytes) }
            }
        }
        return try await FavoriteMutation.perform(repository: repository, operation: {
            try await self.repository.importSynced(retained, assets: assets, budgetBytes: self.settings.imageStorageLimitMiB * 1024 * 1024)
        }, persist: { value in
            if self.settings.saveMode == .afterEachClip { try await self.persist(value) }
        })
    }
    private func capacityBackupURL() throws -> URL {
        try supportDirectory().appendingPathComponent("History Backups", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-before-capacity-eviction.json")
    }

    private func makeCloudSync() throws -> CloudSyncController {
        let file = try supportDirectory().appendingPathComponent("Cloud Sync", isDirectory: true)
            .appendingPathComponent("state.json")
        return CloudSyncController(store: CloudSyncStateStore(url: file), onRemote: { [weak self] entries in
            guard let self else { return }
            let task = await MainActor.run {
                self.enqueue(recordForSync: false) { coordinator in
                    guard let cloud = coordinator.cloudSync else { return }
                    let current = try await coordinator.repository.snapshot()
                    _ = try await cloud.mergeRemoteApplied(entries, into: current) { merged in
                        try await coordinator.acceptSyncedHistory(merged)
                    }
                }
            }
            await task.value
        }, onStatus: { [weak self] status in
            await MainActor.run { self?.setCloudStatus(status) }
        }, onAccountInvalidated: { [weak self] in
            await MainActor.run {
                guard let self else { return }
                self.settings.cloudSyncEnabled = false
                self.settingsStore.save(self.settings)
                self.settingsEditor?.value.cloudSyncEnabled = false
            }
        }, imageSyncEnabled: settings.imageSyncEnabled, imageReader: { [repository] hash in try await repository.imageData(for: hash) }, onRemoteImages: { [weak self] envelopes in
            guard let self else { return }
            let task = await MainActor.run {
                self.enqueue(recordForSync: false) { owner in
                    guard owner.settings.imageSyncEnabled, let cloud = owner.cloudSync else { return }
                    let current = try await owner.repository.snapshot()
                    _ = try await cloud.mergeRemoteApplied(envelopes.map(\.entry), into: current) { merged in
                        try await owner.acceptSyncedHistory(merged, assets: envelopes.compactMap(\.asset))
                    }
                }
            }
            await task.value
        })
    }

    private func deduplicationBackupURL() throws -> URL {
        try supportDirectory().appendingPathComponent("History Backups", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-before-deduplication.json")
    }

    /// Reads a complete disk snapshot before granting writes. A cancelled or failed
    /// recovery leaves the working session and unread destination unchanged.
    private func prepareSaving(force: Bool = false) async throws -> (ready: Bool, restored: HistorySnapshot?) {
        if settings.saveMode != .never && persistence != nil && model.storageWarning == nil && !sessionStartedNever && !force { return (true, nil) }
        persistence = nil
        model.storageWarning = "Saving is paused until saved history is loaded successfully. Export session clippings before quitting or retry in Settings."
        let disk = try SQLiteHistoryRepository(url: try supportDirectory().appendingPathComponent("history.sqlite"))
        let gate = HistoryPersistence(destination: disk)
        let staging = try SQLiteHistoryRepository(inMemory: ())
        try await gate.restore(into: staging)
        let saved = try await staging.snapshot()
        let current = try await repository.snapshot()
        if !saved.recent.isEmpty || !saved.favorites.isEmpty || saved.migration != nil {
            guard confirmRecovery(current, saved) else { return (false, nil) }
            try await repository.replaceAll(saved, assets: staging.exportAssets(for: saved))
            _ = try await history.normalizeRecents(backupTo: try deduplicationBackupURL())
            _ = try await history.enforceCapacities(backupTo: capacityBackupURL())
        }
        configure(settings)
        persistence = gate; sessionStartedNever = false; model.storageWarning = nil
        return (true, (!saved.recent.isEmpty || !saved.favorites.isEmpty || saved.migration != nil) ? saved : nil)
    }

    func shouldOfferMigration() async throws -> Bool {
        guard bundleIdentity == "com.edynamics.flycut" else { return false }
        // Read only marker metadata; save-never must not restore clipboard rows.
        guard try SQLiteHistoryRepository.migrationMarker(at: supportDirectory().appendingPathComponent("history.sqlite")) == nil else { return false }
        return !LegacySourceDiscovery.discover(home: legacyHomeDirectory).sources.isEmpty
    }

    /// Apply the same recovered capacity floor to the editor proposal that will
    /// configure the next capture. A separate later reduction remains possible.
    func applySettings(_ draft: FlycutSettings) async throws -> String? {
        model.message = nil
        var proposed = draft
        var message: String?
        if proposed.cloudSyncEnabled && proposed.saveMode != .afterEachClip {
            proposed.saveMode = .afterEachClip
            message = "Cloud Sync saves local history after each change."
        }
        if proposed.saveMode != .never {
            let preparation = try await prepareSaving()
            guard preparation.ready else { return "Changes cancelled. Export session history before loading saved history." }

        }
        if proposed.openAtLogin != settings.openAtLogin {
            let status = await login.setEnabled(proposed.openAtLogin)
            switch status {
            case .registered: proposed.openAtLogin = true
            case .requiresApproval: message = "Approve Flycut in Login Items Settings."; proposed.openAtLogin = true
            case .notRegistered: proposed.openAtLogin = false
            case .notFound, .error: message = "Login item change failed. Check Login Items Settings."; proposed.openAtLogin = settings.openAtLogin
            }
        }
        let enablingCloud = proposed.cloudSyncEnabled && !settings.cloudSyncEnabled
        if enablingCloud {
            guard bundleIdentity == "com.edynamics.flycut" else {
                return "Cloud Sync is available in the installed Flycut Evolution app."
            }
            let cloud = try makeCloudSync()
            let recovered = try await cloud.prepare(try await repository.snapshot(), reauthorize: true)
            _ = try await acceptSyncedHistory(recovered)
            cloudSync = cloud
        } else if !proposed.cloudSyncEnabled && settings.cloudSyncEnabled {
            await cloudSync?.stop()
            cloudSync = nil
        }
        let limitedHistory = HistoryService(repository: repository, recentCapacity: proposed.recentCapacity, favoriteCapacity: proposed.favoriteCapacity,
                                            archive: proposed.saveMode == .never ? nil : proposed.autoSaveToLocation.map(EvictionArchive.init),
                                            archiveRecents: proposed.saveForgottenClippings, archiveFavorites: proposed.saveForgottenFavorites)
        let beforeLimits = try await repository.snapshot()
        let limitBackup = proposed.saveMode == .never ? nil : try capacityBackupURL()
        let limited = try await FavoriteMutation.perform(repository: repository, operation: {
            _ = try await limitedHistory.enforceCapacities(backupTo: limitBackup)
        }, persist: { value in
            if proposed.saveMode == .afterEachClip { try await self.persist(value, mode: proposed.saveMode) }
        })
        if limited != beforeLimits {
            snapshot = limited; model.updateSnapshot(limited)
            if proposed.cloudSyncEnabled { try await cloudSync?.recordLocal(limited) }
        }
        configure(proposed)
        if enablingCloud { try await cloudSync?.activate() }
        let currentFeedback = [model.message, message].compactMap { $0 }
        return currentFeedback.isEmpty ? "Changes applied." : currentFeedback.joined(separator: " ")
    }

    private func openSettings() {
        shell.dismiss()
        if let settingsWindow { settingsEditor?.value = settings; settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let editor = SettingsModel(settings)
        editor.cloudStatus = cloudStatus
        editor.checkForUpdates = model.checkForUpdates
        editor.showSetup = model.showSetup
        editor.cloudSyncNow = { [weak self, weak editor] in
            guard let self, let editor else { return }
            Task {
                do { try await self.cloudSync?.syncNow() }
                catch { editor.message = "Cloud Sync is unavailable. Local history is safe." }
            }
        }
        settingsEditor = editor
        editor.apply = { [weak self, weak editor] in
            guard let self, let editor else { return }
            editor.busy = true
            enqueue { coordinator in
                defer { editor.busy = false; editor.value = coordinator.settings }
                do {
                    editor.message = try await coordinator.applySettings(editor.value)
                } catch CloudSyncError.unavailable {
                    editor.message = "Cloud Sync is unavailable. Check that this signed app has iCloud access and that your Apple Account is signed in. Local history is safe."
                } catch CloudSyncError.accountChanged {
                    editor.message = "Your Apple Account changed. Review the Cloud Sync notice and enable it again."
                } catch { editor.message = "Changes could not be applied. Saved history is safe; check storage access and retry." }
            }
        }
        editor.importLegacy = { [weak self] in self?.openImport(discover: self?.bundleIdentity == "com.edynamics.flycut") }
        editor.recover = { [weak self, weak editor] in
            self?.enqueue { coordinator in
                do {
                    if try await coordinator.prepareSaving(force: true).ready { editor?.value = coordinator.settings; editor?.message = "Saved history loaded. Choose a save mode and Apply Changes." } else { editor?.message = "Recovery cancelled. Saved history was left untouched; this session remains in memory until recovery succeeds." }
                } catch { editor?.message = "Saved history is still unreadable and was left untouched. Export session clippings before quitting." }
            }
        }
        settingsWindow = makeWindow(title: "Flycut Settings", view: SettingsView(model: editor))
    }
    private func openImport(discover: Bool) {
        if let importWindow { importWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        do {
            let coordinator: MigrationCoordinator
            if let migration { coordinator = migration } else {
                coordinator = MigrationCoordinator(destination: repository, backupDirectory: try supportDirectory().appendingPathComponent("Migration Backups"), memoryDestination: repository)
                migration = coordinator
            }
            let found = discover ? LegacySourceDiscovery.discover(home: legacyHomeDirectory) : nil
            let editor = ImportModel(coordinator: coordinator, working: repository, sources: found?.sources ?? [])
            if !(found?.inaccessibleSources.isEmpty ?? true) { editor.error = "Some legacy sources need file access. Use Choose Preferences File to select them." }
            editor.close = { [weak self] in self?.importWindow?.close(); self?.importWindow = nil }
            editor.performImport = { [weak self] editor in
                guard let self, let source = editor.decision.selectedSource, editor.decision.beginImport() else { return }
                editor.busy = true
                let acceptedChoice = editor.decision.choice
                let acceptedMode = editor.decision.persistentSaveMode
                let acceptedReport = editor.report
                enqueue { owner in
                    defer { editor.busy = false }
                    do {
                        // Preparing disk history can change the destination: require a new preview.
                        let before = try await owner.repository.snapshot()
                        if acceptedReport?.inMemoryOnly == false {
                            guard try await owner.prepareSaving().ready else { editor.decision.failed(); editor.error = "Import cancelled before any source or history was changed."; return }
                            let after = try await owner.repository.snapshot()
                            if before != after { editor.decision.failed(); editor.preview(); return }
                        }
                        let result = try await coordinator.import(source: source, choice: acceptedChoice, persistentSaveMode: acceptedMode, expectedSourceFingerprint: acceptedReport?.sourceFingerprint, expectedDestinationFingerprint: acceptedReport?.destinationFingerprint)
                        _ = try await owner.history.normalizeRecents()
                        var adopted = result.settingsForAdoption(preserving: owner.settings)
                        adopted.recentCapacity = owner.settings.recentCapacity
                        adopted.favoriteCapacity = owner.settings.favoriteCapacity
                        adopted.openAtLogin = owner.settings.openAtLogin
                        adopted.appearance = owner.settings.appearance
                        adopted.rememberPause = owner.settings.rememberPause
                        adopted.autoSaveToLocation = owner.settings.autoSaveToLocation
                        adopted.saveForgottenClippings = owner.settings.saveForgottenClippings
                        adopted.saveForgottenFavorites = owner.settings.saveForgottenFavorites
                        adopted.cloudSyncEnabled = owner.settings.cloudSyncEnabled
                        owner.configure(adopted)
                        _ = try await owner.history.enforceCapacities(backupTo: owner.settings.saveMode == .never ? nil : owner.capacityBackupURL())
                        if owner.settings.saveMode == .afterEachClip { try await owner.persist(owner.repository.snapshot()) }
                        editor.report = result; editor.complete = true; editor.decision.failed(); editor.error = nil
                        owner.settingsEditor?.value = owner.settings
                    } catch { editor.decision.failed(); editor.error = "Import failed. Your source is unchanged. The source or destination may have changed, or file access failed. Retry the preview and confirm again." }
                }
            }
            importWindow = makeWindow(title: "Import Legacy Flycut", view: MigrationView(model: editor))
        } catch { model.message = "Could not open import. Check access to Application Support." }
    }
    private func openSetup() {
        if let setupWindow, setupWindow.isVisible { setupWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let editor = SetupModel(settings: settings, copySample: { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                _ = await paste.copyOrPaste("Flycut plain-text paste test", mode: .copy, previousApp: nil)
            }
        }, save: { [weak self] value, state in
            guard let self else { return }
            var updated = settings
            updated.excludedApplications = value.excludedApplications
            updated.imageCaptureEnabled = value.imageCaptureEnabled
            updated.imageRecognitionEnabled = value.imageRecognitionEnabled
            updated.imageSyncEnabled = value.imageSyncEnabled
            updated.automaticUpdateChecks = value.automaticUpdateChecks
            configure(updated); settingsStore.saveSetup(state); settingsEditor?.value = settings
        })
        setupWindow = makeWindow(title: "Set Up Flycut Evolution", view: SetupView(model: editor, close: { [weak self] in self?.setupWindow?.close() }))
    }
    private func makeWindow<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        monitor?.stop(); hotkey?.unregister(); historyHotkey?.unregister(); pasteTask?.cancel()
        let pending = mutationTask
        Task {
            await pending?.value
            do {
                if settings.saveMode != .never { try await persist(repository.snapshot()) }
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminating = false
                model.message = "History could not be saved. Quit cancelled."
                shell.showPalette()
                sender.reply(toApplicationShouldTerminate: false)
                monitor.start()
                if let registeredHotkey { try? hotkey.register(registeredHotkey) }
                if let registeredHistoryHotkey { try? historyHotkey.register(registeredHistoryHotkey) }
            }
        }
        return .terminateLater
    }
}
