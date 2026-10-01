import CloudKit
import Foundation
import CryptoKit
import FlycutCore

public struct CloudImageEnvelope: Codable, Equatable, Sendable {
    public let entry: CloudClipEntry
    public let asset: ImageAsset?
    public init(entry: CloudClipEntry, asset: ImageAsset?) { self.entry = entry; self.asset = asset }
}
public enum CloudImageCodec {
    public static let recordType = "FlycutImage"
    private static func validate(_ envelope: CloudImageEnvelope) throws {
        guard envelope.entry.isImage else { throw CloudRecordError.malformedRecord }
        if let clip = envelope.entry.clip {
            guard clip.id == envelope.entry.id, let image = clip.image, image.isValid, let asset = envelope.asset,
                  asset.hash == image.assetHash, asset.png.count == image.byteCount else { throw CloudRecordError.malformedRecord }
            let actual = SHA256.hash(data: asset.png).map { String(format: "%02x", $0) }.joined()
            guard actual == asset.hash else { throw CloudRecordError.malformedRecord }
            let decoded = try ClipboardImageDecoder.decode(asset.png, type: "public.png")
            guard decoded.width == image.width, decoded.height == image.height else { throw CloudRecordError.malformedRecord }
        } else if envelope.asset != nil { throw CloudRecordError.malformedRecord }
    }
    public static func record(for envelope: CloudImageEnvelope, zoneID: CKRecordZone.ID, assetDirectory: URL, baseRecord: CKRecord? = nil) throws -> CKRecord {
        try validate(envelope)
        let id = CKRecord.ID(recordName: envelope.entry.id.uuidString, zoneID: zoneID)
        let record = baseRecord?.recordID == id && baseRecord?.recordType == recordType ? baseRecord! : CKRecord(recordType: recordType, recordID: id)
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= 24 * 1024 * 1024 else { throw CloudRecordError.malformedRecord }
        let url = assetDirectory.appendingPathComponent("\(UUID().uuidString).upload")
        try CloudRecordCodec.privateWrite(data, to: url)
        record["payloadAsset"] = CKAsset(fileURL: url)
        return record
    }
    public static func envelope(from record: CKRecord) throws -> CloudImageEnvelope {
        guard record.recordType == recordType, record.recordID.zoneID.zoneName == CloudRecordCodec.zoneName,
              let url = (record["payloadAsset"] as? CKAsset)?.fileURL,
              let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
              size > 0, size <= 24 * 1024 * 1024 else { throw CloudRecordError.malformedRecord }
        let envelope = try JSONDecoder().decode(CloudImageEnvelope.self, from: Data(contentsOf: url))
        guard record.recordID.recordName == envelope.entry.id.uuidString else { throw CloudRecordError.mismatchedIdentifier }
        try validate(envelope)
        return envelope
    }
}
