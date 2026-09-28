import AppKit
import SwiftUI
import FlycutCore

@MainActor final class PaletteModel: ObservableObject {
    @Published var selection = PaletteSelection()
    @Published var isPaused = false
    @Published var message: String?
    @Published var storageWarning: String?
    @Published var needsAccessibility = false
    @Published var showSource = true
    @Published var showHoverPreview = true
    @Published private(set) var hoveredClipID: UUID?
    @Published var previewLength = 40
    @Published var presentation = UUID()
    @Published var previewCount = 10
    @Published var showAll = false
    @Published var showTypes = false
    @Published var backgroundOpacity = 0.25
    @Published var showAccessibilityAlert = false
    private var suppressAccessibilityAlert = false
    private var didExplainAccessibility = false

    var visibleClips: [Clip] {
        let clips = selection.clips
        guard selection.query.isEmpty, !showAll else { return clips }
        let selectedCount = clips.firstIndex { $0.id == selection.selectedID }.map { $0 + 1 } ?? 0
        return Array(clips.prefix(max(previewCount, selectedCount)))
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
    func handleRowClick(_ id: UUID, clickCount: Int) {
        selection.select(id)
        if clickCount == 1 { activateSelection() }
    }
    func handlePlainRowClick(_ id: UUID) {
        selection.select(id)
        perform(.activatePlain)
    }
    func preparePresentation() {
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
    var clear: () -> Void = {}
    var settings: () -> Void = {}
    var about: () -> Void = {}
    var accessibility: () -> Void = {}
    var quit: () -> Void = {}
}
