import AppKit
import SwiftUI
import FlycutCore

enum PalettePresentation {
    static func size(_ settings: FlycutSettings, available: NSSize) -> NSSize {
        NSSize(width: min(max(settings.bezelWidth, 460), max(1, available.width - 32)),
               height: min(max(settings.bezelHeight, 400), max(1, available.height - 32)))
    }
    static func constrain(_ frame: NSRect, to screen: NSRect) -> NSRect {
        let bounds = screen.insetBy(dx: 16, dy: 16)
        return NSRect(x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
                      y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height)),
                      width: frame.width, height: frame.height)
    }
    static func animates(_ settings: FlycutSettings, reduceMotion: Bool) -> Bool {
        settings.popUpAnimation && !reduceMotion
    }
}

@MainActor final class MenuBarController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
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
        panel.contentViewController = NSHostingController(rootView: PaletteView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = "Flycut Evolution"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        keyboard = PaletteKeyboard(model: model) { [weak self] window in
            guard let self, let window else { return false }
            return window === self.panel || window === self.popover.contentViewController?.view.window
        }
    }
    func applyAppearance(_ value: FlycutSettings) {
        settings = value
        updatePresentation(screen: panel.screen ?? NSScreen.main)
        if let button = item.button { MenuBarIcon.configure(button, choice: value.menuIcon) }
    }
    private func updatePresentation(screen: NSScreen?) {
        let size = PalettePresentation.size(settings, available: screen?.visibleFrame.size ?? NSSize(width: 1024, height: 768))
        panel.setContentSize(size)
        if let frame = screen?.visibleFrame { panel.setFrame(PalettePresentation.constrain(panel.frame, to: frame), display: true) }
        popover.contentSize = size
        let animates = PalettePresentation.animates(settings, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        popover.animates = animates
        panel.animationBehavior = animates ? .utilityWindow : .none
    }
    @objc private func toggle() {
        if popover.isShown || panel.isVisible { dismiss(); return }
        guard let button = item.button else { return }
        willPresent()
        updatePresentation(screen: button.window?.screen)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func showPanel() {
        willPresent()
        popover.performClose(nil)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        updatePresentation(screen: screen)
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    /// Keep a sticky panel visible while PasteService activates the destination.
    /// orderFrontRegardless does not make the panel key or activate Flycut.
    func prepareForPaste(sticky: Bool) {
        guard sticky else { dismiss(); return }
        if popover.isShown {
            if let frame = popover.contentViewController?.view.window?.frame {
                panel.setFrameOrigin(frame.origin)
            }
            popover.performClose(nil)
        }
        panel.orderFrontRegardless()
    }

    func dismiss() { popover.performClose(nil); panel.orderOut(nil); didDismiss() }

    func indicateShortcutFailure(_ message: String) {
        item.button?.toolTip = "\(message) Click the Flycut icon for details."
        NSSound.beep()
    }

    func clearShortcutFeedback() {
        item.button?.toolTip = "Flycut clipboard history"
    }
}
