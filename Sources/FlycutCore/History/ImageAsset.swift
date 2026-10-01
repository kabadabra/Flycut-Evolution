import Foundation

public enum ClipContentKind: String, Codable, Sendable { case text, image, file }
public enum ImageRecognitionState: String, Codable, Sendable { case pending, recognized, noText, failed }
public struct ClipImage: Codable, Equatable, Sendable {
    public let assetHash: String
    public let width: Int
    public let height: Int
    public let byteCount: Int
    public var accompanyingText: String?
    public var recognizedText: String?
    public var recognitionState: ImageRecognitionState
    public init(assetHash: String, width: Int, height: Int, byteCount: Int, accompanyingText: String? = nil, recognizedText: String? = nil, recognitionState: ImageRecognitionState = .pending) {
        self.assetHash = assetHash; self.width = width; self.height = height; self.byteCount = byteCount
        self.accompanyingText = accompanyingText; self.recognizedText = recognizedText; self.recognitionState = recognitionState
    }
    public var isValid: Bool { !assetHash.isEmpty && width > 0 && height > 0 && width <= 24_000_000 / height && byteCount > 0 && byteCount <= 16 * 1024 * 1024 }
}
public struct ImageAsset: Codable, Equatable, Sendable {
    public let hash: String
    public let png: Data
    public init(hash: String, png: Data) { self.hash = hash; self.png = png }
}
public struct ImageAssetCapture: Sendable {
    public let asset: ImageAsset
    public let width: Int
    public let height: Int
    public init(asset: ImageAsset, width: Int, height: Int) { self.asset = asset; self.width = width; self.height = height }
}
public protocol ImageAssetRepository: Sendable {
    func imageData(for hash: String) async throws -> Data?
    func applyImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int, recentCapacity: Int) async throws -> HistorySnapshot
    func exportAssets(for snapshot: HistorySnapshot) async throws -> [ImageAsset]
    func replaceAll(_ snapshot: HistorySnapshot, assets: [ImageAsset], expected: HistorySnapshot?) async throws
}
public extension ImageAssetRepository {
    func applyImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int) async throws -> HistorySnapshot {
        try await applyImage(asset, clip: clip, budgetBytes: budgetBytes, recentCapacity: 100_000)
    }
}
public enum ImageBudgetPolicy {
    public static func planEvictions(snapshot: HistorySnapshot, assetSizes: [String: Int], incomingHash: String, incomingBytes: Int, budgetBytes: Int) throws -> [UUID] {
        var recent = snapshot.recent
        var removed: [UUID] = []
        func total() -> Int {
            let hashes = Set((recent + snapshot.favorites).compactMap { $0.image?.assetHash }).union([incomingHash])
            return hashes.reduce(0) { $0 + ($1 == incomingHash ? incomingBytes : assetSizes[$1, default: 0]) }
        }
        while total() > budgetBytes {
            guard let index = recent.lastIndex(where: { $0.image != nil }) else { throw HistoryError.database("Image favorites fill the storage limit. Increase the limit or remove image favorites.") }
            removed.append(recent.remove(at: index).id)
        }
        return removed
    }
}
