import SwiftUI
import FlycutCore
import FlycutPlatform

enum CapturePrivacyControls {
    static let pauseDurations: [TimeInterval] = [300, 900, 3600]
    static func label(_ state: CaptureSessionState) -> String? {
        switch state.pause {
        case .manual: return "Capture paused"
        case .until(let date): return "Capture paused until \(date.formatted(date: .omitted, time: .shortened))"
        case .running: return state.ignoresNextCopy ? "Next copy will be ignored" : nil
        }
    }
}
struct PrivacySettingsView: View {
    @Binding var excluded: [ExcludedApplication]
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            Text("Excluded applications").font(.headline)
            ForEach(excluded) { app in
                HStack {
                    Text(app.displayName).help(app.bundleIdentifier)
                    Spacer()
                    Button("Remove") { excluded.removeAll { $0.id == app.id } }
                }
            }
            HStack {
                Button("Add Application…") {
                    do { if let app = try ExcludedApplicationPicker.chooseApplication(), !excluded.contains(where: { $0.id == app.id }) { excluded.append(app) }; error = nil }
                    catch { self.error = "Choose a valid application bundle. No exclusion was added." }
                }
                Menu("Add Running Application") {
                    ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            let entry = ExcludedApplication(bundleIdentifier: app.bundleIdentifier!, displayName: app.localizedName ?? app.bundleIdentifier!)
                            if !excluded.contains(where: { $0.id == entry.id }) { excluded.append(entry) }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Text("Exclusions use the app active when Flycut observes the copy. Rapid app switches can affect attribution. Existing history is retained. Apply Changes to save.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
