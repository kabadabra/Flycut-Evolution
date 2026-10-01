import XCTest
import AppKit
import CloudKit
@testable import FlycutCore
@testable import FlycutPlatform
final class CloudImageCodecTests: XCTestCase {
    func testImageAssetRoundTripAndLegacyDecoderSkipsIt() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let capture = try ClipboardImageDecoder.decode(bitmap.representation(using: .png, properties: [:])!, type: "public.png")
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: capture.asset.hash, width: 2, height: 2, byteCount: capture.asset.png.count))
        let entry = CloudClipEntry(id: clip.id, clip: clip, changedAt: Date(), origin: "local")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = try CloudImageCodec.record(for: .init(entry: entry, asset: capture.asset), zoneID: .init(zoneName: CloudRecordCodec.zoneName), assetDirectory: folder)
        XCTAssertEqual(record.recordType, "FlycutImage")
        XCTAssertThrowsError(try CloudRecordCodec.entry(from: record))
        let restored = try CloudImageCodec.envelope(from: record)
        XCTAssertEqual(restored.entry, entry); XCTAssertEqual(restored.asset, capture.asset)
        let corrupt = CloudImageEnvelope(entry: entry, asset: .init(hash: capture.asset.hash, png: Data([1,2])))
        XCTAssertThrowsError(try CloudImageCodec.record(for: corrupt, zoneID: .init(zoneName: CloudRecordCodec.zoneName), assetDirectory: folder))
    }
}
