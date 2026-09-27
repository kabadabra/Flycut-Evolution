import AppKit
@preconcurrency import ApplicationServices

@MainActor public struct AccessibilityService {
    private let trust: (Bool) -> Bool
    private let open: (URL) -> Bool
    public init(trust: @escaping (Bool) -> Bool = { prompt in
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }, open: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.trust = trust; self.open = open
    }
    public var isTrusted: Bool { trust(false) }
    /// Requests the system prompt; permission can only be granted by the user in Settings.
    @discardableResult public func requestPermission() -> Bool { trust(true) }
    @discardableResult public func openSettings() -> Bool {
        open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
