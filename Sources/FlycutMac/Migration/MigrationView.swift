import SwiftUI
import FlycutCore
import FlycutPlatform

@MainActor final class ImportModel: ObservableObject {
    @Published var decision: MigrationViewModel
    @Published var report: MigrationReport?
    @Published var error: String?
    @Published var complete = false
    @Published var busy = false
    let coordinator: MigrationCoordinator
    let working: any HistoryRepository
    var performImport: (ImportModel) -> Void = { _ in }
    var close: () -> Void = {}
    private var previewTask: Task<Void, Never>?
    init(coordinator: MigrationCoordinator, working: any HistoryRepository, sources: [LegacySource]) {
        self.coordinator = coordinator; self.working = working
        decision = MigrationViewModel(sources: sources)
    }
    func select(_ source: LegacySource) { decision.select(source); complete = false; preview() }
    func chooseFile() { if let source = LegacySourcePicker.chooseSource() { select(source) } }
    func preview() {
        previewTask?.cancel(); decision.invalidatePreview(); report = nil; error = nil; busy = true
        guard let source = decision.selectedSource else { busy = false; return }
        let saveMode = decision.persistentSaveMode, choice = decision.choice
        previewTask = Task {
            do {
                let value = try await coordinator.preview(source: source, destination: working, choice: choice, persistentSaveMode: saveMode)
                guard !Task.isCancelled else { return }
                report = value
                decision.acceptPreview(destinationCount: value.destinationCount, inMemoryOnly: value.inMemoryOnly, importableCount: value.recentCount + value.favoriteCount)
            } catch { if !Task.isCancelled { self.error = "This preferences file could not be read. Choose a valid Flycut plist or retry after granting file access." } }
            if !Task.isCancelled { busy = false }
        }
    }
    func cancel() { previewTask?.cancel(); decision.cancel(); report = nil; close() }
}

struct MigrationView: View {
    @ObservedObject var model: ImportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Legacy Flycut").font(.title)
            Text("Quit Flycut 2.0 first. Select one source and review it before importing. Your source file is left unchanged.")
            Picker("Source", selection: Binding(get: { model.decision.selectedSource?.identity ?? "" }, set: { identity in
                if let source = model.decision.sources.first(where: { $0.identity == identity }) { model.select(source) }
            })) {
                Text("Choose a source").tag("")
                ForEach(model.decision.sources, id: \.identity) { source in Text(source.displayDomain ?? source.url.lastPathComponent).tag(source.identity) }
            }.disabled(model.busy || model.complete)
            Button("Choose Preferences File…", action: model.chooseFile).disabled(model.busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let report = model.report {
                        Text(report.source.url.path).font(.caption).textSelection(.enabled)
                        Text("Source: \(report.recentCount) recent · \(report.favoriteCount) favorites\nDestination: \(report.destinationRecentCount) recent · \(report.destinationFavoriteCount) favorites")
                        Text("Resulting capacities: \(report.settings.recentCapacity) recent · \(report.settings.favoriteCapacity) favorites")
                        Text("Imported settings: save mode \(report.settings.saveMode == .never ? "Never" : report.settings.saveMode == .onQuit ? "On quit" : "After each change"), password protection \(report.settings.skipPasswordFields ? "on" : "off"). Open at Login and automatic export folders require a separate choice in Settings.").font(.caption)
                        Text("Legacy menu previews become the initial palette rows; Show All and search reach every clipping. Palette dimensions fit the screen with a usable minimum. Single-click, Return and accessible activation copy a clipping, then paste when an editable field is focused. New formatted copies paste with their saved styling; the text icon on those rows pastes plain text. The default Shift-Command-V shortcut pastes the current clipboard as plain text. The old copy-versus-paste preference no longer controls activation. Background opacity applies over native material. Accessibility reminders appear once per session unless suppressed.").font(.caption).foregroundStyle(.orange)
                        ForEach(Array(report.warnings.filter { !$0.hasPrefix("Skipped ") }.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) }
                        ForEach(Array(report.skipped.enumerated()), id: \.offset) { _, entry in Text("Skipped \(entry.collection.rawValue) entry \(entry.index + 1): \(entry.reason)").font(.caption) }
                        if model.complete {
                            Text(report.alreadyImported ? "This source was already imported. Existing settings were retained." : "Imported \(report.importedCount) clippings.").font(.headline)
                            if let path = report.sourceBackup { backup("Source backup", path) }
                            if let path = report.destinationBackup { backup("Destination backup", path) }
                            if report.inMemoryOnly { Text("History and backups remain in memory for this session.") }
                        } else {
                            if report.inMemoryOnly || model.decision.storage != .choose {
                                Picker("Imported history storage", selection: $model.decision.storage) {
                                    Text("Choose storage").tag(MigrationViewModel.Storage.choose)
                                    Text("Memory only — preserve save-never").tag(MigrationViewModel.Storage.memory)
                                    Text("Save on quit").tag(MigrationViewModel.Storage.onQuit)
                                    Text("Save after each change").tag(MigrationViewModel.Storage.afterEachClip)
                                }.onChange(of: model.decision.storage) { _ in model.preview() }
                            }
                            if report.destinationCount > 0 {
                                Picker("Destination behavior", selection: $model.decision.action) {
                                    Text("Choose behavior").tag(MigrationViewModel.Action.choose)
                                    Text("Merge with existing history").tag(MigrationViewModel.Action.merge)
                                    Text("Replace existing history").tag(MigrationViewModel.Action.replace)
                                }.onChange(of: model.decision.action) { _ in model.preview() }
                            }
                            Text(report.inMemoryOnly ? "Backups stay in memory." : "A private source backup and a backup of any replaced or merged destination will be created before import.").font(.caption)
                            Toggle("I reviewed this source, warnings, storage and destination choice", isOn: $model.decision.confirmed)
                        }
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red); Button("Retry Preview", action: model.preview) }
                }.frame(maxWidth: .infinity, alignment: .leading).disabled(model.busy)
            }
            HStack {
                Button(model.complete ? "Done" : "Cancel", action: model.cancel).disabled(model.decision.importing)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                if !model.complete { Button("Import") { model.performImport(model) }.disabled(model.busy || !model.decision.canImport) }
            }
        }.padding(24).frame(width: 620, height: 610)
    }
    private func backup(_ title: String, _ url: URL) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(url.path)").font(.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button("Show \(title.lowercased())") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
