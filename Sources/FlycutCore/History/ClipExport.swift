import Foundation

/// Mixed collections keep metadata and PNG bytes together in a portable JSON file.
public struct ClipExport: Sendable {
    public struct Collection: Codable, Equatable, Sendable {
        public let formatVersion: Int
        public let clips: [Clip]
        public let imageAssets: [ImageAsset]
    }
    public let filename: String
    public let data: Data
    public static func make(_ clips: [Clip], assets: [ImageAsset]) throws -> ClipExport {
        let hashes = Set(clips.compactMap { $0.image?.assetHash })
        let included = assets.filter { hashes.contains($0.hash) }
        guard hashes.isSubset(of: Set(included.map(\.hash))) else { throw HistoryError.database("Image export data is unavailable") }
        if clips.count == 1, let hash = clips[0].image?.assetHash {
            return ClipExport(filename: "Flycut.png", data: included.first { $0.hash == hash }!.png)
        }
        if hashes.isEmpty && !clips.contains(where: { $0.files != nil }) {
            return ClipExport(filename: "Flycut.txt", data: Data(clips.reversed().map(\.text).joined(separator: "\n").utf8))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return ClipExport(filename: "Flycut.json", data: try encoder.encode(Collection(formatVersion: 1, clips: clips, imageAssets: included)))
    }
}
