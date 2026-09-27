import Foundation

/// Decisions that can be made without reading application metadata or writing history.
public enum CapturePolicy {
    public static func accepts(
        text: String,
        advertisedTypes: [String],
        settings: FlycutSettings
    ) -> Bool {
        guard !text.isEmpty else { return false }
        if settings.skipPasswordFields && advertisedTypes.contains("PasswordPboardType") { return false }
        if settings.skipPasteboardTypes {
            let blocked = Set(settings.skippedPasteboardTypes)
            if advertisedTypes.contains(where: blocked.contains) { return false }
        }
        if settings.skipPasswordLengths && settings.skippedPasswordLengths.contains(text.count) { return false }
        return true
    }
}
