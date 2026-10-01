import AppKit
import SwiftUI
import FlycutCore

@MainActor final class PaletteModel: ObservableObject {
    var images = ImagePreviewModel()
    @Published var previewImageID: UUID?
    var copyExtractedText: (UUID) -> Void = { _ in }
    var retryRecognition: (UUID) -> Void = { _ in }
    func closeImagePreview() { previewImageID = nil; images.cancel() }
    @Published var selection = PaletteSelection() {
        didSet {
            if selection.query != oldValue.query || selection.collection != oldValue.collection || selection.snapshotRevision != oldValue.snapshotRevision { scheduleSearch() }
        }
    }
    @Published var isPaused = false
    @Published var captureState = CaptureSessionState()
    @Published var message: String?
    @Published var storageWarning: String?
    @Published var needsAccessibility = false
    @Published var showSource = true
    @Published var showHoverPreview = true
    @Published private(set) var hoveredClipID: UUID?
    @Published var previewLength = 40
    @Published var presentation = UUID() { didSet { scheduleSearch() } }
    @Published var previewCount = 10
    @Published var showAll = false
    @Published var showTypes = false
    @Published var backgroundOpacity = 0.25
    @Published var showAccessibilityAlert = false
    private var suppressAccessibilityAlert = false
    private var didExplainAccessibility = false

    @Published private(set) var searchResults: [ClipSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var editedFavoriteID: UUID?
    @Published var favoriteEdit = FavoriteEdit(name: "", text: "")
    @Published private(set) var favoriteSaving = false
    @Published private(set) var favoriteError: String?
    private(set) var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var presentationActive = true
    private var resultByID: [UUID: ClipSearchResult] = [:]
    private var editGeneration = UUID()
    var searchProvider: @Sendable (String, [Clip]) async -> [ClipSearchResult] = { query, clips in ClipSearch.search(query, in: clips) }
    var saveFavorite: (UUID, FavoriteEdit) async throws -> Void = { _,_ in throw HistoryError.database("Favorite editing unavailable") }
    var moveFavorite: (UUID, Int) async throws -> Void = { _,_ in throw HistoryError.database("Favorite ordering unavailable") }

    var visibleClips: [Clip] {
        let clips = selection.clips
        guard selection.query.isEmpty, selection.collection == .recent, !showAll else { return clips }
        let favorites = clips.filter { $0.collection == .favorite }
        let recents = clips.filter { $0.collection == .recent }
        let selectedCount = recents.firstIndex { $0.id == selection.selectedID }.map { $0 + 1 } ?? 0
        return favorites + Array(recents.prefix(max(previewCount, selectedCount)))
    }
    var conflictingFavoriteIDs: Set<UUID> {
        let favorites = selection.allClips.filter { $0.collection == .favorite }
        let groups = Dictionary(grouping: favorites.filter { $0.favoriteMetadata?.shortcut != nil }, by: { $0.favoriteMetadata!.shortcut! })
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }
    func updateSnapshot(_ snapshot: HistorySnapshot) { selection.update(snapshot) }
    func result(for id: UUID) -> ClipSearchResult? { resultByID[id] }
    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchResults = []; resultByID = [:]
        guard presentationActive, !selection.query.isEmpty else { isSearching = false; searchTask = nil; return }
        isSearching = true
        let query = selection.query, clips = selection.filteredSourceClips, provider = searchProvider
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let worker = Task.detached(priority: .userInitiated) { await provider(query, clips) }
            let results = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
            self.searchResults = results
            self.resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.clip.id, $0) })
            self.selection.setSearchResults(results.map(\.clip))
            self.isSearching = false
        }
    }
    func cancelPresentation() {
        presentationActive = false
        searchGeneration += 1; searchTask?.cancel(); searchTask = nil; isSearching = false
        clearHover(); cancelFavoriteEdit(); closeImagePreview()
    }
    func beginFavoriteEdit(_ id: UUID) {
        guard !favoriteSaving, let clip = selection.clip(id: id), clip.collection == .favorite else { return }
        editGeneration = UUID(); editedFavoriteID = id; favoriteError = nil
        favoriteEdit = .init(name: clip.favoriteMetadata?.name ?? "", text: clip.text, shortcut: clip.favoriteMetadata?.shortcut)
    }
    func cancelFavoriteEdit() { editGeneration = UUID(); editedFavoriteID = nil; favoriteError = nil; favoriteSaving = false }
    func saveFavoriteEdit() async {
        guard !favoriteSaving, let id = editedFavoriteID else { return }
        guard selection.clip(id: id)?.collection == .favorite else { favoriteError = "This favorite was deleted. Cancel to return to history."; return }
        guard favoriteEdit.name.count <= 200, selection.clip(id: id)?.image != nil || !favoriteEdit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            favoriteError = "Enter content and a name of at most 200 characters."; return
        }
        let generation = editGeneration, edit = favoriteEdit
        favoriteSaving = true; favoriteError = nil
        do {
            try await saveFavorite(id, edit)
            guard editGeneration == generation else { return }
            favoriteSaving = false; editedFavoriteID = nil
        } catch {
            guard editGeneration == generation else { return }
            favoriteSaving = false
            favoriteError = error as? HistoryError == .shortcutInUse ? "That shortcut is assigned to another favorite. Choose a different number." : "Could not save this favorite. Your draft is kept; check saved-history access and try again."
        }
    }
    func canMoveFavorite(_ id: UUID, offset: Int) -> Bool {
        let favorites = selection.allClips.filter { $0.collection == .favorite }
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return false }
        return favorites.indices.contains(index + offset)
    }
    func moveFavoriteRow(_ id: UUID, offset: Int) {
        Task { [weak self] in
            guard let self else { return }
            do { try await moveFavorite(id, offset) }
            catch { message = "Could not reorder favorites. Try again." }
        }
    }
    func apply(_ settings: FlycutSettings) {
        selection.wraparound = settings.wraparoundPalette
        showSource = settings.displayClippingSource
        showHoverPreview = settings.showHoverPreview
        previewLength = settings.previewCharacterCount
        previewCount = settings.menuPreviewCount
        showTypes = settings.revealPasteboardTypes
        backgroundOpacity = settings.bezelAlpha
        suppressAccessibilityAlert = settings.suppressAccessibilityAlert
    }
    func activateSelection() {
        guard selection.selected != nil else { return }
        perform(.activate)
    }
    func activateVisibleNumber(_ number: Int) {
        guard editedFavoriteID == nil, (1...9).contains(number), visibleClips.indices.contains(number-1) else { return }
        perform(.activateID(visibleClips[number-1].id))
    }
    func activateFavoriteSlot(_ slot: Int) {
        guard editedFavoriteID == nil else { return }
        switch FavoriteShortcuts.resolve(slot: slot, favorites: selection.allClips.filter { $0.collection == .favorite }) {
        case .clip(let id): perform(.activateID(id))
        case .missing: break
        case .conflict: message = "Favorite shortcut conflicts. Edit your favorites to assign different numbers."
        }
    }
    func handleRowClick(_ id: UUID, clickCount: Int) {
        selection.select(id)
        if clickCount == 1 { activateSelection() }
    }
    func handlePlainRowClick(_ id: UUID) {
        selection.select(id)
        perform(.activatePlain)
    }
    func preparePresentation() {
        cancelPresentation()
        presentationActive = true
        selection.query = ""
        selection.collection = .recent
        selection.home()
        showAll = false
        presentation = UUID()
    }
    func copyToTop(_ id: UUID) { perform(.copyToTop(id)) }
    func rowHovered(_ id: UUID, inside: Bool) {
        if inside { hoveredClipID = id }
        else if hoveredClipID == id { hoveredClipID = nil }
    }
    func clearHover() { hoveredClipID = nil }
    func reportAccessibilityDenied() {
        message = "Copied. Allow Accessibility access to paste automatically."
        needsAccessibility = true
        if !suppressAccessibilityAlert && !didExplainAccessibility {
            showAccessibilityAlert = true
            didExplainAccessibility = true
        }
    }
    var perform: (PaletteCommand) -> Void = { _ in }
    var pause: () -> Void = {}
    var pauseFor: (TimeInterval?) -> Void = { _ in }
    var ignoreNextCopy: () -> Void = {}
    var cancelIgnoreNextCopy: () -> Void = {}
    var clear: () -> Void = {}
    var settings: () -> Void = {}
    var about: () -> Void = {}
    var accessibility: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var showSetup: () -> Void = {}
    var quit: () -> Void = {}
}
