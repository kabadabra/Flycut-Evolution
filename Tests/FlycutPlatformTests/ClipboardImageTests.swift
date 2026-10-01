import XCTest
import AppKit
import ImageIO
@testable import FlycutCore
@testable import FlycutPlatform
final class ClipboardImageTests: XCTestCase {
    func testNormalizeSupportedImageAndRejectCorruptOrOversized() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let image = try ClipboardImageDecoder.decode(png, type: "public.png")
        XCTAssertEqual(image.width, 2); XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.asset.hash.count, 64)
        XCTAssertThrowsError(try ClipboardImageDecoder.decode(Data([1,2,3]), type: "public.png"))
        XCTAssertThrowsError(try ClipboardImageDecoder.decode(Data(repeating: 0, count: 16 * 1024 * 1024 + 1), type: "public.png"))
        XCTAssertThrowsError(try ClipboardImageDecoder.decode(png, type: "public.file-url"))
        var huge = png
        huge.replaceSubrange(16..<24, with: [0,0,0x19,0,0,0,0x19,0])
        XCTAssertThrowsError(try ClipboardImageDecoder.decode(huge, type: "public.png"))
    }
    func testImagePreferencesPreserveExistingAndValidateBounds() {
        let freshDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let fresh = SettingsStore(defaults: freshDefaults).load()
        XCTAssertTrue(fresh.imageCaptureEnabled)
        XCTAssertFalse(fresh.imageSyncEnabled)
        let oldDefaults = UserDefaults(suiteName: UUID().uuidString)!
        oldDefaults.set(40, forKey: "v3.recentCapacity")
        let store = SettingsStore(defaults: oldDefaults)
        var old = store.load()
        XCTAssertFalse(old.imageCaptureEnabled)
        old.imageCaptureEnabled = true; old.imageStorageLimitMiB = 3000
        store.save(old)
        XCTAssertTrue(store.load().imageCaptureEnabled)
        XCTAssertEqual(store.load().imageStorageLimitMiB, 2048)
    }
}
