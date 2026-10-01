import AppKit
import FlycutCore

/// Local monitor only handles events in the palette's own window.
@MainActor final class PaletteKeyboard {
    enum DigitAction: Equatable { case visible(Int), favorite(Int) }
    static func modifiedDigit(key: String, modifiers: NSEvent.ModifierFlags) -> DigitAction? {
        guard key.count == 1, let digit = Int(key), (1...9).contains(digit) else { return nil }
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        if flags == .command { return .visible(digit) }
        if flags == [.command, .option] { return .favorite(digit) }
        return nil
    }
    private var monitor: Any?
    init(model: PaletteModel, owns: @escaping (NSWindow?) -> Bool) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard owns(event.window) else { return event }
            guard model.editedFavoriteID == nil, model.previewImageID == nil else { return event }
            if let digit = Self.modifiedDigit(key: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags) {
                switch digit {
                case .visible(let number): model.activateVisibleNumber(number)
                case .favorite(let slot): model.activateFavoriteSlot(slot)
                }
                return nil
            }
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
