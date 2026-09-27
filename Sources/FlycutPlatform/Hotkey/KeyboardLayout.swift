import Carbon

/// Resolves the command layer (including layouts such as Dvorak-QWERTY Command).
@MainActor public struct KeyboardLayout {
    private let translate: (UInt16) -> String?
    public init(translate: @escaping (UInt16) -> String?) { self.translate = translate }
    public init() {
        translate = { code in
            let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            guard let bytes = CFDataGetBytePtr(data) else { return nil }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKey: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8),
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                        &deadKey, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
    public func label(for keyCode: Int) -> String {
        guard (0...127).contains(keyCode) else { return "Unknown key" }
        return translate(UInt16(keyCode))?.uppercased() ?? "Key \(keyCode)"
    }
    public func keyCode(for character: String) -> UInt16? {
        (UInt16(0)...UInt16(127)).first { translate($0)?.lowercased() == character.lowercased() }
    }
}
