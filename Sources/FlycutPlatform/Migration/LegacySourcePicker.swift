import AppKit
import FlycutCore
import UniformTypeIdentifiers

@MainActor
public enum LegacySourcePicker {
    /// User-selected files also handle legacy containers that discovery cannot read.
    public static func chooseSource() -> LegacySource? {
        let panel = NSOpenPanel()
        panel.title = "Choose Flycut Preferences"
        panel.message = "Choose a legacy Flycut .plist file to preview its history and settings."
        panel.allowedContentTypes = [UTType(filenameExtension: "plist") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return LegacySource(url: url)
    }
}
