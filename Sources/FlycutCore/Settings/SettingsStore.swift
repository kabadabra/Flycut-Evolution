import Foundation

public struct SettingsStore {
    private let defaults: UserDefaults
    private let prefix = "v3."
    private let paletteSizeMigrationKey = "v3.evolutionPaletteSizeMigrated"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> FlycutSettings {
        migratePaletteSizeIfNeeded()
        let fallback = FlycutSettings()
        guard let data = try? JSONEncoder().encode(fallback),
              var dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return fallback
        }
        for key in Array(dictionary.keys) + ["saveToLocation", "autoSaveToLocation"] {
            guard let value = defaults.object(forKey: prefix + key) else { continue }
            var trial = dictionary
            trial[key] = value
            guard let trialData = try? JSONSerialization.data(withJSONObject: trial),
                  (try? JSONDecoder().decode(FlycutSettings.self, from: trialData)) != nil else {
                continue
            }
            dictionary = trial
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: dictionary),
              var decoded = try? JSONDecoder().decode(FlycutSettings.self, from: merged) else {
            return fallback
        }
        decoded.validate()
        return decoded
    }

    public func save(_ value: FlycutSettings) {
        var settings = value
        settings.validate()
        guard let data = try? JSONEncoder().encode(settings),
              let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        for (key, value) in dictionary {
            defaults.set(value, forKey: prefix + key)
        }
        defaults.removeObject(forKey: prefix + "removeDuplicates")
        defaults.removeObject(forKey: prefix + "syncSettingsViaICloud")
        defaults.removeObject(forKey: prefix + "syncClippingsViaICloud")
        defaults.set(true, forKey: paletteSizeMigrationKey)
        if settings.saveToLocation == nil { defaults.removeObject(forKey: prefix + "saveToLocation") }
        if settings.autoSaveToLocation == nil { defaults.removeObject(forKey: prefix + "autoSaveToLocation") }
    }

    private func migratePaletteSizeIfNeeded() {
        guard !defaults.bool(forKey: paletteSizeMigrationKey) else { return }
        if defaults.object(forKey: prefix + "bezelWidth") != nil,
           defaults.object(forKey: prefix + "bezelHeight") != nil,
           defaults.double(forKey: prefix + "bezelWidth") == 500,
           defaults.double(forKey: prefix + "bezelHeight") == 320 {
            defaults.set(460.0, forKey: prefix + "bezelWidth")
            defaults.set(700.0, forKey: prefix + "bezelHeight")
        }
        defaults.set(true, forKey: paletteSizeMigrationKey)
    }
}
