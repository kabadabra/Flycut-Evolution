import Foundation

public struct LegacySettingsMapping: Sendable {
    public let settings: FlycutSettings
    public let warnings: [String]
}

public enum LegacySettingsMapper {
    public static func map(_ preferences: [String: Any]) -> LegacySettingsMapping {
        var settings = FlycutSettings()
        var warnings: [String] = []
        let nested = preferences["store"] as? [String: Any] ?? [:]

        func value(_ key: String) -> Any? { preferences[key] ?? nested[key] }
        func integer(_ key: String, default fallback: Int, valid: (Int) -> Bool = { $0 >= 0 }) -> Int {
            guard let raw = value(key) else { return fallback }
            guard let number = raw as? NSNumber, number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,
                  number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max),
                  valid(number.intValue) else {
                warnings.append("Unsupported value for \(key); using default.")
                return fallback
            }
            return number.intValue
        }
        func boolean(_ key: String, default fallback: Bool) -> Bool {
            guard let raw = value(key) else { return fallback }
            guard let number = raw as? NSNumber,
                  number.doubleValue == 0 || number.doubleValue == 1 else {
                warnings.append("Unsupported value for \(key); using default.")
                return fallback
            }
            return number.boolValue
        }
        func double(_ key: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
            guard let raw = value(key) else { return fallback }
            guard let number = raw as? NSNumber, number.doubleValue.isFinite else {
                warnings.append("Unsupported value for \(key); using default.")
                return fallback
            }
            let result = min(max(number.doubleValue, range.lowerBound), range.upperBound)
            if result != number.doubleValue { warnings.append("Clamped \(key) to supported range.") }
            return result
        }
        func csv(_ key: String, default fallback: [String]) -> [String] {
            guard let raw = value(key) else { return fallback }
            guard let list = raw as? String else {
                warnings.append("Unsupported value for \(key); using default.")
                return fallback
            }
            return list.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        func fileURL(_ key: String) -> URL? {
            guard let raw = value(key) else { return nil }
            let url: URL?
            if let direct = raw as? URL { url = direct }
            else if let text = raw as? String { url = URL(string: text) }
            else if let data = raw as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = nil }
            guard let url, url.isFileURL, !url.path.isEmpty, url.absoluteString.utf8.count <= 4096 else {
                warnings.append("Unsupported file URL for \(key); ignoring it.")
                return nil
            }
            return url
        }

        settings.recentCapacity = integer("rememberNum", default: 40) { $0 > 0 }
        settings.favoriteCapacity = integer("favoritesRememberNum", default: 40) { $0 > 0 }
        settings.menuPreviewCount = integer("displayNum", default: 10) { $0 > 0 }
        settings.previewCharacterCount = integer("displayLen", default: 40) { $0 > 0 }
        settings.saveMode = SaveMode(rawValue: integer("savePreference", default: 1)) ?? .onQuit
        if let raw = value("savePreference") as? NSNumber, SaveMode(rawValue: raw.intValue) == nil {
            warnings.append("Unsupported savePreference; using on-quit saving.")
        }
        settings.skipPasswordFields = boolean("skipPasswordFields", default: true)
        settings.skipPasteboardTypes = boolean("skipPboardTypes", default: true)
        settings.skippedPasteboardTypes = csv("skipPboardTypesList", default: settings.skippedPasteboardTypes)
        settings.skipPasswordLengths = boolean("skipPasswordLengths", default: false)
        let lengths = csv("skipPasswordLengthsList", default: ["12", "20", "32"])
        settings.skippedPasswordLengths = lengths.compactMap { part in
            guard let number = Int(part), number > 0 else {
                warnings.append("Unsupported skipPasswordLengthsList entry; ignoring it.")
                return nil
            }
            return number
        }
        settings.revealPasteboardTypes = boolean("revealPasteboardTypes", default: false)
        settings.pasteMovesToTop = boolean("pasteMovesToTop", default: false)
        settings.menuIcon = integer("menuIcon", default: 0) { (0...2).contains($0) }
        settings.bezelAlpha = double("bezelAlpha", default: 0.25, range: 0...1)
        settings.stickyPalette = boolean("stickyBezel", default: false)
        settings.wraparoundPalette = boolean("wraparoundBezel", default: false)
        settings.openAtLogin = boolean("loadOnStartup", default: false)
        settings.menuSelectionPastes = boolean("menuSelectionPastes", default: true)
        settings.bezelWidth = double("bezelWidth", default: 460, range: 200...1600)
        settings.bezelHeight = double("bezelHeight", default: 700, range: 160...1200)
        settings.popUpAnimation = boolean("popUpAnimation", default: false)
        settings.displayClippingSource = boolean("displayClippingSource", default: true)
        settings.saveForgottenClippings = boolean("saveForgottenClippings", default: false)
        settings.saveForgottenFavorites = boolean("saveForgottenFavorites", default: true)
        settings.suppressAccessibilityAlert = boolean("suppressAccessibilityAlert", default: false)
        settings.saveToLocation = fileURL("saveToLocation")
        settings.autoSaveToLocation = fileURL("autoSaveToLocation")

        if let raw = value("ShortcutRecorder mainHotkey") {
            if let dictionary = raw as? [String: Any],
               let code = dictionary["keyCode"] as? NSNumber,
               let flags = dictionary["modifierFlags"] as? NSNumber,
               code.doubleValue.isFinite,
               flags.doubleValue.isFinite,
               code.doubleValue.rounded() == code.doubleValue,
               flags.doubleValue.rounded() == flags.doubleValue,
               (0...127).contains(code.doubleValue),
               (0...Double(UInt32.max)).contains(flags.doubleValue) {
                settings.hotkey = FlycutHotkey(keyCode: code.intValue, modifierFlags: flags.intValue)
            } else {
                warnings.append("Unsupported ShortcutRecorder mainHotkey; using Shift-Command-V.")
            }
        }
        if boolean("syncSettingsViaICloud", default: false) {
            warnings.append("Old iCloud settings sync was not imported; device settings stay on this Mac.")
        }
        if boolean("syncClippingsViaICloud", default: false) {
            warnings.append("Old iCloud clipping sync was not imported; enable Cloud Sync in Evolution after reviewing it.")
        }
        settings.validate()
        return LegacySettingsMapping(settings: settings, warnings: warnings)
    }
}
