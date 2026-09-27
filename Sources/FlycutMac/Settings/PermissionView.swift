import SwiftUI
import FlycutPlatform
struct PermissionView: View {
    @State private var trusted = AccessibilityService().isTrusted
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trusted ? "Accessibility access is enabled." : "Copy works without Accessibility. Allow Accessibility to paste into other apps.")
            VStack(alignment: .leading) {
                Button("Request Accessibility") { trusted = AccessibilityService().requestPermission() }
                Button("Open Accessibility Settings") { AccessibilityService().openSettings() }
                Button("Refresh") { trusted = AccessibilityService().isTrusted }
            }
            Text("Flycut reads changed text copies and available RTF formatting while capture is running. Pause capture from the palette whenever needed. No clipboard content is sent to analytics.").font(.caption)
        }
    }
}
