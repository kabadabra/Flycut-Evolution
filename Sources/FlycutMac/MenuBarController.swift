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

@MainActor final class MenuBarController: NSObject, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover: NSPopover
    var willPresent: () -> Void = {}
    var didDismiss: () -> Void = {}
    private var settings = FlycutSettings()
    private var keyboard: PaletteKeyboard?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    init(model: PaletteModel, popover: NSPopover = NSPopover()) {
        self.popover = popover
        super.init()
        if let button = item.button { MenuBarIcon.configure(button, choice: settings.menuIcon) }
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: 460, height: 700)
        popover.contentViewController = NSHostingController(rootView: PaletteView(model: model))
        keyboard = PaletteKeyboard(model: model) { [weak self] window in
            guard let self, let window else { return false }
            return window === self.popover.contentViewController?.view.window
        }
    }
    isolated deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
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
    func togglePalette() {
        if popover.isShown { dismiss() } else { showPalette() }
    }
    func showPalette() {
        guard let button = item.button else { return }
        willPresent()
        updatePresentation(screen: button.window?.screen)
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.behavior = .applicationDefined
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        installOutsideClickMonitors()
    }
    /// A sticky palette remains attached to the status item while the destination activates.
    func prepareForPaste(sticky: Bool) {
        guard sticky else { dismiss(cancelPaste: false); return }
        popover.behavior = .applicationDefined
    }

    func dismiss(cancelPaste: Bool = true) {
        removeOutsideClickMonitors()
        if cancelPaste { didDismiss() }
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown(event) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown(event) }
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard popover.isShown else { return }
        let paletteWindow = popover.contentViewController?.view.window
        var window = event.window
        while let current = window {
            if current === paletteWindow { return }
            window = current.parent
        }
        // Leave the status button to toggle the palette on mouse-up. Closing on
        // mouse-down would make that same click reopen it.
        if let button = item.button, let window = button.window, event.window === window {
            let point = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(point) { return }
        }
        dismiss()
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    func indicateShortcutFailure(_ message: String) {
        item.button?.toolTip = "\(message) Click the Flycut icon for details."
        NSSound.beep()
    }

    func clearShortcutFeedback() {
        item.button?.toolTip = "Flycut clipboard history"
    }
}
