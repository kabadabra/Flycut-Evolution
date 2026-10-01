import XCTest
import AppKit
import FlycutCore
@testable import FlycutPlatform

@MainActor final class FileClipboardTests: XCTestCase {
    private func png() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }
    func testFinderImageFileCapturesPixelsInsteadOfFilename() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("image with spaces.png")
        try png().write(to: url)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var texts: [Clip] = [], images: [Clip] = [], assets: [ImageAsset] = []
        let monitor = ClipboardMonitor(pasteboard: SystemPasteboardClient(pasteboard: board), settings: { FlycutSettings() }, source: { .init(appName: "Finder", bundleURL: nil) }, onClip: { texts.append($0) })
        monitor.onImage = { images.append($0); assets.append($1) }
        let captured = expectation(description: "image decoded")
        monitor.onImage = { images.append($0); assets.append($1); captured.fulfill() }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([url as NSURL]))
        _ = board.setString(url.lastPathComponent, forType: .string)
        monitor.pollOnce()
        await fulfillment(of: [captured], timeout: 2)
        XCTAssertTrue(texts.isEmpty)
        XCTAssertEqual(images.first?.image?.width, 3)
        XCTAssertEqual(images.first?.image?.height, 2)
        XCTAssertFalse(assets.isEmpty)
    }
    func testFilesWithoutTextRepresentationAreCaptured() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var clips: [Clip] = []
        let monitor = ClipboardMonitor(pasteboard: SystemPasteboardClient(pasteboard: board), settings: { FlycutSettings() }, onClip: { clips.append($0) })
        let urls = [URL(fileURLWithPath: "/tmp/first report.pdf"), URL(fileURLWithPath: "/tmp/second.txt")]
        board.clearContents()
        XCTAssertTrue(board.writeObjects(urls.map { $0 as NSURL }))
        monitor.pollOnce()
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips.first?.pasteboardType, "public.file-url")
        XCTAssertEqual(clips.first?.text, "first report.pdf\nsecond.txt")
    }
    func testExcludedFinderDoesNotReadFileContents() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var settings = FlycutSettings()
        settings.excludedApplications = [.init(bundleIdentifier: "com.apple.finder", displayName: "Finder")]
        let monitor = ClipboardMonitor(pasteboard: SystemPasteboardClient(pasteboard: board), settings: { settings }, source: { .init(appName: "Finder", bundleURL: nil, bundleIdentifier: "com.apple.finder") }, onClip: { _ in XCTFail("Excluded file was captured") })
        monitor.onImage = { _, _ in XCTFail("Excluded image was captured") }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([URL(fileURLWithPath: "/tmp/excluded.png") as NSURL]))
        monitor.pollOnce()
    }
    func testDisabledImageCaptureKeepsFileReferenceWithoutReadingPixels() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var settings = FlycutSettings(); settings.imageCaptureEnabled = false
        var clips: [Clip] = []
        let monitor = ClipboardMonitor(pasteboard: SystemPasteboardClient(pasteboard: board), settings: { settings }, onClip: { clips.append($0) })
        monitor.onImage = { _, _ in XCTFail("Disabled image capture decoded pixels") }
        board.clearContents()
        XCTAssertTrue(board.writeObjects([URL(fileURLWithPath: "/tmp/not-readable.png") as NSURL]))
        monitor.pollOnce()
        XCTAssertEqual(clips.first?.files?.first?.path, "/tmp/not-readable.png")
        XCTAssertNil(clips.first?.image)
    }

}
