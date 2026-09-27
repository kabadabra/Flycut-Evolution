import AppKit
import FlycutCore

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Local monitor only handles events in the palette's own windows.
@MainActor final class PaletteKeyboard {
    private var monitor: Any?
    init(model: PaletteModel, owns: @escaping (NSWindow?) -> Bool) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard owns(event.window) else { return event }
            let editing = event.window?.firstResponder is NSTextView
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if modifiers == .command, event.charactersIgnoringModifiers == "f" {
                model.presentation = UUID(); return nil
            }
            guard modifiers.isEmpty else { return event }
            switch event.keyCode {
            case 125: model.selection.move(1)
            case 126: model.selection.move(-1)
            case 115 where !editing: model.selection.home()
            case 119 where !editing: model.selection.end()
            case 116 where !editing: model.selection.move(-10)
            case 121 where !editing: model.selection.move(10)
            default:
                guard let action = PaletteCommand.resolve(keyCode: event.keyCode, key: event.characters ?? "", editingSearch: editing) else { return event }
                model.perform(action)
            }
            return nil
        }
    }
    isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
