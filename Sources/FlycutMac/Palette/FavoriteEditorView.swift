import SwiftUI
import FlycutCore

struct FavoriteEditorView: View {
    @ObservedObject var model: PaletteModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Favorite").font(.title2.bold())
            TextField("Name (optional)", text: $model.favoriteEdit.name).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Favorite name")
            if let id = model.editedFavoriteID, model.selection.clip(id: id)?.contentKind != .text {
                Label("The original image or file reference is kept. You can edit its name and shortcut.", systemImage: "photo")
            } else {
            Text("Content").font(.headline)
            TextEditor(text: $model.favoriteEdit.text)
                .font(.body).padding(5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Favorite content")
            }
            if let id = model.editedFavoriteID, model.selection.clip(id: id)?.formattedRTF != nil {
                Label("Changing the content removes its saved formatting. Renaming keeps it.", systemImage: "textformat")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Palette shortcut", selection: $model.favoriteEdit.shortcut) {
                Text("None").tag(nil as Int?)
                ForEach(1...9, id: \.self) { Text("⌥⌘\($0)").tag(Optional($0)) }
            }
            Text("This shortcut works while clipboard history is open, even when this favorite is hidden by search.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.favoriteError { Text(error).font(.callout).foregroundStyle(.red).accessibilityLabel(error) }
            HStack {
                Button("Cancel", action: model.cancelFavoriteEdit).keyboardShortcut(.cancelAction)
                Spacer()
                if model.favoriteSaving { ProgressView().controlSize(.small) }
                Button("Save Favorite") { Task { await model.saveFavoriteEdit() } }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(16).disabled(model.favoriteSaving)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onExitCommand { if !model.favoriteSaving { model.cancelFavoriteEdit() } }
    }
}
