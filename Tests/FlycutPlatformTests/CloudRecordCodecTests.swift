import CloudKit
import Foundation
import XCTest
import FlycutCore
@testable import FlycutPlatform

final class CloudRecordCodecTests: XCTestCase {
    private func entry(text: String?, id: UUID = UUID()) -> CloudClipEntry {
        let clip = text.map { Clip(id: id, text: $0, pasteboardType: "public.utf8-plain-text", sourceAppName: "Test",
                                   sourceBundleURL: nil, capturedAt: Date(timeIntervalSince1970: 10), collection: .recent, order: 0) }
        return CloudClipEntry(id: id, clip: clip, changedAt: Date(timeIntervalSince1970: 20), origin: "Mac-A")
    }

    func testSmallClipAndTombstoneRoundTripThroughPrivateRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zone = CKRecordZone.ID(zoneName: "FlycutEvolution")
        for value in [entry(text: "Synthetic text"), entry(text: nil)] {
            let record = try CloudRecordCodec.record(for: value, zoneID: zone, assetDirectory: directory)
            XCTAssertEqual(record.recordID.recordName, value.id.uuidString)
            XCTAssertEqual(try CloudRecordCodec.entry(from: record), value)
        }
    }

    func testFormattedClipRoundTripsThroughEncryptedCloudField() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let rtf = Data("{\\rtf1\\ansi\\b Styled}".utf8)
        let clip = Clip(id: id, text: "Styled", pasteboardType: "public.utf8-plain-text", sourceAppName: "Test",
                        sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0,
                        formattedRTF: rtf)
        let entry = CloudClipEntry(id: id, clip: clip, changedAt: Date(timeIntervalSince1970: 20), origin: "Mac-A")
        let record = try CloudRecordCodec.record(for: entry, zoneID: CKRecordZone.ID(zoneName: "FlycutEvolution"),
                                                 assetDirectory: directory)
        XCTAssertNotNil(record.encryptedValues["payload"])
        XCTAssertEqual(try CloudRecordCodec.entry(from: record).clip?.formattedRTF, rtf)
    }

    func testLargeClipUsesProtectedAssetAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = entry(text: String(repeating: "x", count: 900_000))
        let record = try CloudRecordCodec.record(for: value, zoneID: CKRecordZone.ID(zoneName: "FlycutEvolution"), assetDirectory: directory)
        let asset = try XCTUnwrap(record["payloadAsset"] as? CKAsset)
        let file = try XCTUnwrap(asset.fileURL)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try CloudRecordCodec.entry(from: record), value)
    }

    func testMalformedOrMismatchedRecordIsRejected() throws {
        let zone = CKRecordZone.ID(zoneName: "FlycutEvolution")
        let record = CKRecord(recordType: "FlycutClip", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        XCTAssertThrowsError(try CloudRecordCodec.entry(from: record))
        let value = entry(text: "Synthetic")
        let encoded = try JSONEncoder().encode(value)
        record.encryptedValues["payload"] = encoded
        XCTAssertThrowsError(try CloudRecordCodec.entry(from: record))
    }
}
