import AppKit
import Carbon
import FlycutCore

public enum HotkeyError: Error, Equatable { case conflict, system(Int32), invalidShortcut }
@MainActor public protocol HotkeyClient: AnyObject {
    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) -> Int32
    func unregister()
}

@MainActor public final class HotkeyService {
    private let client: any HotkeyClient
    private let onPress: @MainActor () -> Void
    private var registered = false
    public init(client: any HotkeyClient = CarbonHotkeyClient(), onPress: @escaping @MainActor () -> Void = {}) {
        self.client = client; self.onPress = onPress
    }
    isolated deinit { if registered { client.unregister() } }
    public func register(_ shortcut: FlycutHotkey) throws {
        guard (0...127).contains(shortcut.keyCode), shortcut.modifierFlags >= 0 else { throw HotkeyError.invalidShortcut }
        unregister()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.modifierFlags))
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        let status = client.register(keyCode: UInt32(shortcut.keyCode), modifiers: carbon, onPress: onPress)
        guard status == noErr else { throw status == eventHotKeyExistsErr ? HotkeyError.conflict : .system(status) }
        registered = true
    }
    public func unregister() { if registered { client.unregister(); registered = false } }
}

@MainActor public final class CarbonHotkeyClient: HotkeyClient {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?
    public init() {}
    isolated deinit { unregister() }
    public func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) -> Int32 {
        unregister()
        self.onPress = onPress
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x464C5943, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<CarbonHotkeyClient>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { unregister(); return installed }
        let result = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x464C5943, id: 1),
                                         GetApplicationEventTarget(), 0, &hotkey)
        if result != noErr { unregister() }
        return result
    }
    public func unregister() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
        hotkey = nil; handler = nil; onPress = nil
    }
}
