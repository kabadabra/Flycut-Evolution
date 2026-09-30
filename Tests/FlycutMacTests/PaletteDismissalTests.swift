import AppKit
import XCTest
@testable import FlycutMac

@MainActor final class PaletteDismissalTests: XCTestCase {
    func testPaletteClosesOnOutsideClicksBeforeAndAfterStickyPaste() {
        _ = NSApplication.shared
        let shell = MenuBarController(model: PaletteModel(), popover: TestPopover())
        defer { shell.dismiss(); NSStatusBar.system.removeStatusItem(shell.item) }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        for sticky in [false, true] {
            for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
                showPalette(shell)
                if sticky { shell.prepareForPaste(sticky: true) }
                XCTAssertTrue(shell.popover.isShown)
                let event = mouseDown(type, in: window)
                NSApp.sendEvent(event)
                XCTAssertFalse(shell.popover.isShown, "Outside click must dismiss, sticky=\(sticky), type=\(type)")
            }
        }
    }

    func testClicksInPaletteAndStatusButtonDoNotDismissOnMouseDown() {
        _ = NSApplication.shared
        let shell = MenuBarController(model: PaletteModel(), popover: TestPopover())
        defer { shell.dismiss(); NSStatusBar.system.removeStatusItem(shell.item) }
        showPalette(shell)
        guard let window = shell.popover.contentViewController?.view.window,
              let button = shell.item.button, let statusWindow = button.window else {
            XCTFail("Palette and status button need windows: shown=\(shell.popover.isShown), status=\(String(describing: shell.item.button?.window)), visible=\(shell.item.isVisible)"); return
        }
        NSApp.sendEvent(mouseDown(.rightMouseDown, in: window))
        XCTAssertTrue(shell.popover.isShown)
        let buttonPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        NSApp.sendEvent(mouseDown(.rightMouseDown, in: statusWindow, at: buttonPoint))
        XCTAssertTrue(shell.popover.isShown, "Mouse-up owns status button toggling")
    }

    private func showPalette(_ shell: MenuBarController) {
        shell.showPalette()
        XCTAssertTrue(shell.popover.isShown)
    }

    private func mouseDown(_ type: NSEvent.EventType, in window: NSWindow,
                           at point: NSPoint = NSPoint(x: 50, y: 50)) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil,
                           eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    func testClosingForPasteDoesNotCancelPasteRequest() {
        _ = NSApplication.shared
        let shell = MenuBarController(model: PaletteModel(), popover: TestPopover())
        var cancellations = 0
        shell.didDismiss = { cancellations += 1 }
        showPalette(shell)
        shell.prepareForPaste(sticky: false)
        XCTAssertFalse(shell.popover.isShown)
        XCTAssertEqual(cancellations, 0)
        NSStatusBar.system.removeStatusItem(shell.item)
    }
}

/// Keep AppKit presentation out of event-routing tests: real status-item
/// popovers can be closed by unrelated mouse events in the user's session.
@MainActor private final class TestPopover: NSPopover {
    private var presented = false
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
    override var isShown: Bool { presented }
    override func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        window.contentViewController = contentViewController
        presented = true
    }
    override func close() { presented = false }
}
