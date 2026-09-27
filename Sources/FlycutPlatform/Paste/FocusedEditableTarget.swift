import ApplicationServices

enum FocusedEditableTarget {
    static func isEditable(processID: pid_t) -> Bool {
        focusedEditable(processID: processID) != nil
    }

    /// Replaces only the destination selection. The general pasteboard remains
    /// unchanged, including rich text and any clipboard item not yet captured.
    static func insertPlainText(_ text: String, processID: pid_t) -> Bool {
        guard let element = focusedEditable(processID: processID) else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private static func focusedEditable(processID: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(processID)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return nil }

        var enabled: CFTypeRef?
        let enabledStatus = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        // AXEnabled is optional for some editable views. An explicit false is
        // authoritative; an unsupported attribute is not evidence of read-only text.
        if enabledStatus == .success, let enabled = enabled as? Bool, !enabled { return nil }

        var valueSettable = DarwinBoolean(false)
        let valueStatus = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        var selectionSettable = DarwinBoolean(false)
        let selectionStatus = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectionSettable)
        guard (valueStatus == .success && valueSettable.boolValue) ||
              (selectionStatus == .success && selectionSettable.boolValue) else { return nil }
        return element
    }
}
