import AppKit
import SwiftUI
import FlycutCore

enum PalettePresentation {
    static func size(_ settings: FlycutSettings, available: NSSize) -> NSSize {
        NSSize(width: min(max(settings.bezelWidth, 460), max(1, available.width - 32)),
               height: min(max(settings.bezelHeight, 400), max(1, available.height - 32)))
    }
    static func animates(_ settings: FlycutSettings, reduceMotion: Bool) -> Bool {
        settings.popUpAnimation && !reduceMotion
    }
}

@MainActor final class MenuBarController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    var willPresent: () -> Void = {}
    var didDismiss: () -> Void = {}
    private var settings = FlycutSettings()
    private var keyboard: PaletteKeyboard?
    init(model: PaletteModel) {
        super.init()
        if let button = item.button { MenuBarIcon.configure(button, choice: settings.menuIcon) }
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 700)
        popover.contentViewController = NSHostingController(rootView: PaletteView(model: model))
        keyboard = PaletteKeyboard(model: model) { [weak self] window in
            guard let self, let window else { return false }
            return window === self.popover.contentViewController?.view.window
        }
    }
    func applyAppearance(_ value: FlycutSettings) {
        settings = value
        updatePresentation(screen: item.button?.window?.screen ?? NSScreen.main)
        if let button = item.button { MenuBarIcon.configure(button, choice: value.menuIcon) }
    }
    private func updatePresentation(screen: NSScreen?) {
        let size = PalettePresentation.size(settings, available: screen?.visibleFrame.size ?? NSSize(width: 1024, height: 768))
        popover.contentSize = size
        let animates = PalettePresentation.animates(settings, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        popover.animates = animates
    }
    @objc private func toggle() {
        if popover.isShown { dismiss(); return }
        showPalette()
    }
    func showPalette() {
        guard let button = item.button else { return }
        willPresent()
        updatePresentation(screen: button.window?.screen)
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.behavior = .transient
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }
    /// A sticky palette remains attached to the status item while the destination activates.
    func prepareForPaste(sticky: Bool) {
        guard sticky else { dismiss(); return }
        popover.behavior = .applicationDefined
    }

    func dismiss() { popover.performClose(nil); didDismiss() }

    func indicateShortcutFailure(_ message: String) {
        item.button?.toolTip = "\(message) Click the Flycut icon for details."
        NSSound.beep()
    }

    func clearShortcutFeedback() {
        item.button?.toolTip = "Flycut clipboard history"
    }
}
