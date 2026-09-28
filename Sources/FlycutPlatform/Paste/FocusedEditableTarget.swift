import ApplicationServices
import AppKit

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
        var selectedRange: CFTypeRef?
        let hasSelectionRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success
            && selectedRange != nil
        guard (valueStatus == .success && valueSettable.boolValue) ||
              (selectionStatus == .success && selectionSettable.boolValue) || hasSelectionRange else { return nil }
        return element
    }

    /// Only use Teams' compose shortcut when the active window has one composer.
    static func hasTeamsComposer(processID: pid_t) -> Bool {
        guard NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "com.microsoft.teams2" else { return false }
        let app = AXUIElementCreateApplication(processID)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return false }
        var queue = [windowValue as! AXUIElement]
        var next = 0
        var candidates = 0
        while next < queue.count && next < 5000 {
            let element = queue[next]
            next += 1
            if isTeamsComposer(element) {
                candidates += 1
                if candidates > 1 { return false }
            }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return candidates == 1 && next == queue.count
    }

    private static func isTeamsComposer(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              roleValue as? String == kAXTextAreaRole else { return false }
        var descriptionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionValue) == .success,
              let description = descriptionValue as? String else { return false }
        return description == "Type a message"
    }
}
