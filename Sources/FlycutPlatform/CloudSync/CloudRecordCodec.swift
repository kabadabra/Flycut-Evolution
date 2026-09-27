import CloudKit
import Foundation
import Darwin
import FlycutCore

public enum CloudRecordError: Error, Equatable {
    case malformedRecord
    case mismatchedIdentifier
    case unableToWriteAsset
}

public enum CloudRecordCodec {
    public static let zoneName = "FlycutEvolution"
    public static let recordType = "FlycutClip"
    private static let inlineLimit = 512_000

    public static func record(for entry: CloudClipEntry, zoneID: CKRecordZone.ID, assetDirectory: URL,
                              baseRecord: CKRecord? = nil) throws -> CKRecord {
        let id = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record = baseRecord?.recordID == id && baseRecord?.recordType == recordType
            ? baseRecord! : CKRecord(recordType: recordType, recordID: id)
        record.encryptedValues["payload"] = nil
        record["payloadAsset"] = nil
        let data = try JSONEncoder().encode(entry)
        if data.count <= inlineLimit {
            record.encryptedValues["payload"] = data
        } else {
            let url = assetDirectory.appendingPathComponent("\(UUID().uuidString).upload")
            try privateWrite(data, to: url)
            record["payloadAsset"] = CKAsset(fileURL: url)
        }
        return record
    }

    public static func entry(from record: CKRecord) throws -> CloudClipEntry {
        guard record.recordType == recordType,
              record.recordID.zoneID.zoneName == zoneName else { throw CloudRecordError.malformedRecord }
        let data: Data
        if let inline = record.encryptedValues["payload"] as? Data { data = inline }
        else if let file = (record["payloadAsset"] as? CKAsset)?.fileURL { data = try Data(contentsOf: file) }
        else { throw CloudRecordError.malformedRecord }
        let entry = try JSONDecoder().decode(CloudClipEntry.self, from: data)
        guard record.recordID.recordName == entry.id.uuidString else { throw CloudRecordError.mismatchedIdentifier }
        return entry
    }

    private static func privateWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CloudRecordError.unableToWriteAsset }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
