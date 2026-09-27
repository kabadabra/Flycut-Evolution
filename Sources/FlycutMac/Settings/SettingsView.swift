import SwiftUI
import FlycutCore
import FlycutPlatform

@MainActor final class SettingsModel: ObservableObject {
    @Published var value: FlycutSettings
    @Published var message: String?
    @Published var busy = false
    @Published var cloudStatus: CloudSyncStatus = .off
    var apply: () -> Void = {}
    var cloudSyncNow: () -> Void = {}
    var importLegacy: () -> Void = {}
    var recover: () -> Void = {}
    init(_ value: FlycutSettings) { self.value = value }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var typesText = ""
    @State private var lengthsText = ""
    private var shortcutLabel: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(model.value.hotkey.modifierFlags))
        return [(NSEvent.ModifierFlags.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")].compactMap { flags.contains($0.0) ? $0.1 : nil }.joined(separator: "–") + "–" + KeyboardLayout().label(for: model.value.hotkey.keyCode)
    }
    var body: some View {
        VStack {
            TabView {
                general.tabItem { Label("General", systemImage: "gear") }
                shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
                privacy.tabItem { Label("Privacy", systemImage: "lock") }
                cloudSync.tabItem { Label("Cloud Sync", systemImage: "icloud") }
                appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
                AboutView().tabItem { Label("About", systemImage: "info.circle") }
            }
            if let message = model.message { Text(message).font(.callout).textSelection(.enabled) }
            HStack { Spacer(); Button("Apply Changes", action: applyEdited).keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 600, height: 570).disabled(model.busy)
        .onAppear { syncLists() }
        .onChange(of: model.value.skippedPasteboardTypes) { _ in syncLists() }
        .onChange(of: model.value.skippedPasswordLengths) { _ in syncLists() }
    }
    private func syncLists() {
        typesText = model.value.skippedPasteboardTypes.joined(separator: ", ")
        lengthsText = model.value.skippedPasswordLengths.map(String.init).joined(separator: ", ")
    }
    private func applyEdited() {
        let pieces = lengthsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let lengths = pieces.compactMap(Int.init)
        guard pieces.count == lengths.count && lengths.allSatisfy({ $0 > 0 }) else {
            model.message = "Enter positive whole-number lengths separated by commas."; return
        }
        model.value.skippedPasteboardTypes = typesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.value.skippedPasswordLengths = lengths
        model.message = nil
        model.apply()
    }
    private var general: some View {
        ScrollView { Form {
            Toggle("Open at Login", isOn: $model.value.openAtLogin)
            Button("Open Login Items Settings", action: LoginItemService.openSettings)
            Stepper("Recent capacity: \(model.value.recentCapacity)", value: $model.value.recentCapacity, in: 1...100000)
            Stepper("Favorite capacity: \(model.value.favoriteCapacity)", value: $model.value.favoriteCapacity, in: 1...100000)
            Picker("Save history", selection: $model.value.saveMode) {
                Text("Never — memory only").tag(SaveMode.never)
                Text("On quit").tag(SaveMode.onQuit)
                Text("After each change").tag(SaveMode.afterEachClip)
            }
            Text("Never keeps this session in memory. Previously saved history remains on disk. Enabling saving asks how to handle it before writing.").font(.caption)
            Toggle("Move copied or pasted clippings to top", isOn: $model.value.pasteMovesToTop)
            Toggle("Export recents before capacity eviction", isOn: $model.value.saveForgottenClippings)
            Toggle("Export favorites before capacity eviction", isOn: $model.value.saveForgottenFavorites)
            Button("Choose Automatic Export Folder…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                if panel.runModal() == .OK { model.value.autoSaveToLocation = panel.url }
            }
            Text(model.value.autoSaveToLocation?.path ?? "Choose a folder to enable automatic exports. Disabled in save-never mode.").font(.caption)
            Button("Import Legacy Flycut…", action: model.importLegacy)
            Button("Retry Saved History…", action: model.recover)
        }.padding() }
    }
    private var shortcuts: some View {
        Form {
            Text("Paste current clipboard as plain text: \(shortcutLabel)")
            ShortcutRecorder(hotkey: $model.value.hotkey)
                .frame(height: 36)
            Button("Reset to Shift–Command–V") { model.value.hotkey = FlycutSettings().hotkey }
            Text("The menu bar icon opens your clippings. Single-click a clipping or press Return to paste it with its saved formatting when available. Use the text icon beside a formatted clipping to paste that clipping without formatting. If no field is selected, it stays on the clipboard.").font(.caption)
            Toggle("Keep palette open after copy or paste", isOn: $model.value.stickyPalette)
            Toggle("Wrap selection at first and last clipping", isOn: $model.value.wraparoundPalette)
            Text("In the palette: arrows or j/k select, Return activates, Escape closes, f favorites, F switches lists, s exports, S exports the list. Type in search to filter.").font(.callout)
        }.padding()
    }
    private var privacy: some View {
        ScrollView { VStack(alignment: .leading, spacing: 10) {
            Toggle("Remember capture pause across launches", isOn: $model.value.rememberPause)
            Toggle("Skip password fields", isOn: $model.value.skipPasswordFields)
            Toggle("Skip sensitive clipboard types", isOn: $model.value.skipPasteboardTypes)
            TextField("Skipped types (comma separated)", text: $typesText)
            Toggle("Skip these text lengths", isOn: $model.value.skipPasswordLengths)
            TextField("Lengths (comma separated)", text: $lengthsText)
            Toggle("Show saved pasteboard type in clipping rows", isOn: $model.value.revealPasteboardTypes)
            Toggle("Suppress automatic Accessibility reminder", isOn: $model.value.suppressAccessibilityAlert)
            Text("Copy fallback and the Accessibility Settings link remain available.").font(.caption)
            PermissionView()
        }.padding() }
    }
    private var cloudSync: some View {
        Form {
            Toggle("Sync history and favorites across my Macs", isOn: $model.value.cloudSyncEnabled)
            Text("Turning this on uploads existing and future text clippings, including saved RTF formatting when available, to your private iCloud account. Other Macs signed into the same Apple Account can receive them after you enable sync there. Settings remain on each Mac.")
                .font(.caption)
            Text("Cloud Sync saves local history after each change. Turning sync off keeps your local history and previously synced cloud history.")
                .font(.caption)
            Text(cloudStatusLabel).font(.callout)
            Button("Sync Now", action: model.cloudSyncNow).disabled(!model.value.cloudSyncEnabled)
        }.padding()
    }
    private var cloudStatusLabel: String {
        switch model.cloudStatus {
        case .off: "Cloud Sync is off."
        case .connecting: "Connecting to iCloud…"
        case .syncing: "Syncing with iCloud…"
        case .upToDate(let date): date.map { "Last synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Connected to iCloud."
        case .accountChanged: "Apple Account changed. Enable sync again to choose this account."
        case .unavailable: "iCloud is unavailable. Check your Apple Account and connection."
        case .error(let detail): detail
        }
    }
    private var appearance: some View {
        ScrollView { Form {
            Picker("Appearance", selection: $model.value.appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }
            Picker("Menu bar icon", selection: $model.value.menuIcon) {
                Text("Clipboard").tag(0); Text("Scissors").tag(1); Text("Text").tag(2)
            }
            Toggle("Show clipping source", isOn: $model.value.displayClippingSource)
            Toggle("Show full clipping preview on hover", isOn: $model.value.showHoverPreview)
            Stepper("Initial preview rows: \(model.value.menuPreviewCount)", value: $model.value.menuPreviewCount, in: 1...1000)
            Text("Show All, search and keyboard navigation reach the full history.").font(.caption)
            Stepper("Preview characters: \(model.value.previewCharacterCount)", value: $model.value.previewCharacterCount, in: 1...1000)
            TextField("Palette width", value: $model.value.bezelWidth, format: .number)
            TextField("Palette height", value: $model.value.bezelHeight, format: .number)
            Text("Minimum 460 × 400 points; constrained to the current screen.").font(.caption)
            Slider(value: $model.value.bezelAlpha, in: 0...1) { Text("Background opacity") }
            Text("Adds an opaque backing over the native material; text stays fully opaque.").font(.caption)
            Toggle("Animate palette opening", isOn: $model.value.popUpAnimation)
            Text("Animations are disabled when Reduce Motion is on.").font(.caption)
        }.padding() }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotkey: FlycutHotkey
    func makeNSView(context: Context) -> RecorderButton { let view = RecorderButton(); view.title = "Record Shortcut…"; view.bezelStyle = .rounded; view.target = view; view.action = #selector(RecorderButton.beginRecording); return view }
    func updateNSView(_ view: RecorderButton, context: Context) { view.record = { hotkey = $0 } }
}
private final class RecorderButton: NSButton {
    var record: (FlycutHotkey) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { window?.makeFirstResponder(self); title = "Press a shortcut (Escape cancels)" }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { title = "Record Shortcut…"; window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty else { title = "Include Command, Control or Option"; return }
        record(FlycutHotkey(keyCode: Int(event.keyCode), modifierFlags: Int(flags.rawValue)))
        title = "Shortcut recorded — Apply Changes"; window?.makeFirstResponder(nil)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }; keyDown(with: event); return true
    }
}
