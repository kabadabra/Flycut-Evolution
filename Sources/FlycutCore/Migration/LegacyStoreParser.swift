import Foundation

public enum LegacyStoreParser {
    public static func parse(data: Data) throws -> LegacySnapshot {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw MigrationError.invalidPropertyList
        }
        guard let store = root["store"] as? [String: Any] else { throw MigrationError.absentStore }
        let mapping = LegacySettingsMapper.map(root)
        var warnings = mapping.warnings
        var skipped: [SkippedLegacyRecord] = []
        if store["version"] as? String != "0.7" { warnings.append("Unrecognized store version; recognized clipping fields will be imported.") }
        func parseList(_ key: String, kind: CollectionKind) -> [Clip] {
            guard let raw = store[key] else { return [] }
            guard let list = raw as? [Any] else {
                warnings.append("\(key) is not an array; the collection cannot be imported.")
                return []
            }
            return list.enumerated().compactMap { index, value in
                guard let item = value as? [String: Any], let text = item["Contents"] as? String,
                      let type = item["Type"] as? String else {
                    skipped.append(SkippedLegacyRecord(collection: kind, index: index, reason: "Missing or invalid Contents or Type."))
                    return nil
                }
                func optionalString(_ key: String) -> String? {
                    guard let raw = item[key] else { return nil }
                    if let result = raw as? String { return result }
                    warnings.append("\(kind.rawValue) record \(index): unsupported \(key); metadata omitted.")
                    return nil
                }
                var date: Date?
                if let raw = item["Timestamp"] {
                    if let number = raw as? NSNumber, number.doubleValue.isFinite {
                        date = Date(timeIntervalSince1970: number.doubleValue)
                    } else { warnings.append("\(kind.rawValue) record \(index): unsupported Timestamp; metadata omitted.") }
                }
                return Clip(id: UUID(), text: text, pasteboardType: type,
                            sourceAppName: optionalString("AppLocalizedName"), sourceBundleURL: optionalString("AppBundleURL"),
                            capturedAt: date, collection: kind, order: index)
            }
        }
        let recent = parseList("jcList", kind: .recent)
        let favorites = parseList("favoritesList", kind: .favorite)
        var settings = mapping.settings
        settings.recentCapacity = max(settings.recentCapacity, recent.count)
        settings.favoriteCapacity = max(settings.favoriteCapacity, favorites.count)
        for item in skipped { warnings.append("Skipped \(item.collection.rawValue) record \(item.index): \(item.reason)") }
        return LegacySnapshot(history: HistorySnapshot(recent: recent, favorites: favorites), settings: settings, skipped: skipped, warnings: warnings)
    }
}
