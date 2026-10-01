import AppKit
import FlycutCore

@MainActor public enum ExcludedApplicationPicker {
    public static func application(at url: URL) throws -> ExcludedApplication {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, !id.isEmpty else { throw HistoryError.database("Choose an application with a bundle identifier.") }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        return .init(bundleIdentifier: id, displayName: name)
    }
    public static func chooseApplication() throws -> ExcludedApplication? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try application(at: url)
    }
}
