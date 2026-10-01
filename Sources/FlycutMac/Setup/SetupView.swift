import SwiftUI
import FlycutCore

struct SetupView: View {
    @ObservedObject var model: SetupModel
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set Up Flycut Evolution").font(.title.bold())
            Text("Step \(model.state.step.rawValue + 1) of 5").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.state.step {
                    case .privacy:
                        Text("Choose what enters history").font(.headline)
                        Text("Capture runs while the app is open. Use Ignore Next Copy or pause for 5 minutes, 15 minutes, or an hour from the history menu.")
                        Toggle("Capture copied images and screenshots", isOn: $model.value.imageCaptureEnabled)
                        Toggle("Recognize text locally for search", isOn: $model.value.imageRecognitionEnabled)
                        PrivacySettingsView(excluded: $model.value.excludedApplications)
                    case .shortcuts:
                        Text("Open History").font(.headline)
                        Text("Option–Command–V opens searchable clipboard history. Choose a clipping with arrows and Return, or click it to paste. Favorites support names and assigned number shortcuts.")
                        Text("Paste without formatting").font(.headline)
                        Text("Shift–Command–V pastes the current clipboard as plain text. You can customize both shortcuts in Settings. Use Copy Extracted Text on an image for recognized text.")
                    case .permissions:
                        Text("Allow automatic paste").font(.headline)
                        Text(model.trusted ? "Accessibility access is enabled." : "Copy works without permission. Accessibility lets Flycut paste into your focused application.")
                        Button("Request Accessibility", action: model.requestPermission)
                        Button("Open Accessibility Settings", action: model.openPermissionSettings)
                        Button("Refresh Status", action: model.refreshPermission)
                    case .paste:
                        Text("Try a plain-text paste").font(.headline)
                        Text("Copy this harmless sample, click a text field in an application you use, then press Shift–Command–V. Return here to confirm the result. Nothing is sent automatically.")
                        Button("Copy Sample Text", action: model.copySample)
                        if model.sampleCopied { Text("Sample copied: Flycut plain-text paste test") }
                        HStack {
                            Button("It Pasted Correctly") { model.confirmPaste(true) }
                            Button("It Did Not Paste") { model.confirmPaste(false) }
                        }
                        if let succeeded = model.pasteSucceeded { Text(succeeded ? "Thanks — your paste test is confirmed." : "Check Accessibility in the previous step, and focus a text field before retrying.") }
                    case .updates:
                        Text("Choose optional connections").font(.headline)
                        Toggle("Check for signed updates automatically", isOn: $model.value.automaticUpdateChecks)
                        Text("Checks contact the release server. Downloads and installation need your choice. Manual checks are always available.")
                        Toggle("Sync images with my Macs", isOn: $model.value.imageSyncEnabled)
                        Text("Image sync also requires Cloud Sync enabled in Settings, and image sync enabled on each Mac. It uploads images and recognized text to your private iCloud account.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Skip Setup") { model.dismiss(); close() }
                Spacer()
                if model.state.step != .privacy { Button("Back", action: model.back) }
                if model.state.step == .updates { Button("Finish") { model.finish(); close() }.keyboardShortcut(.defaultAction) }
                else { Button("Next", action: model.next).keyboardShortcut(.defaultAction) }
            }
        }.padding(24).frame(width: 560, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission() }
        .onDisappear { model.dismiss() }
    }
}
