import XCTest
import AppKit
import FlycutCore
@testable import FlycutMac
@MainActor final class ImagePaletteTests: XCTestCase {
    func testThumbnailCacheIsBoundedAndMissingImageIsGentle() async {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let model = ImagePreviewModel(read: { _ in png })
        for number in 0..<130 { await model.loadThumbnail(hash: String(number)) }
        XCTAssertLessThanOrEqual(model.thumbnails.count, 128)
        let missing = ImagePreviewModel(read: { _ in nil })
        await missing.load(hash: "missing")
        XCTAssertNil(missing.preview)
        XCTAssertNotNil(missing.error)
    }
    func testImageFavoriteAcceptsEmptyText() async {
        let model = PaletteModel()
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .favorite, order: 0, image: .init(assetHash: "one", width: 1, height: 1, byteCount: 1))
        model.updateSnapshot(.init(recent: [], favorites: [clip]))
        model.beginFavoriteEdit(clip.id)
        var saved = false
        model.saveFavorite = { _, _ in saved = true }
        await model.saveFavoriteEdit()
        XCTAssertTrue(saved)
    }
    func testPreviewTransitionsPreservePanelSizeAndLiveSearch() async throws {
        let model = PaletteModel()
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "test", width: 500, height: 100, byteCount: 3, recognizedText: "OCR fixture", recognitionState: .recognized))
        model.updateSnapshot(.init(recent: [clip], favorites: []))
        let shell = MenuBarController(model: model)
        shell.showPalette()
        defer { shell.dismiss(); NSStatusBar.system.removeStatusItem(shell.item) }
        try await Task.sleep(for: .milliseconds(150))
        let size = shell.popover.contentSize
        model.previewImageID = clip.id
        try await Task.sleep(for: .milliseconds(150))
        model.closeImagePreview()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(shell.popover.contentSize, size, "Changing palette content must not shrink its configured viewport")
        model.selection.query = "OCR"
        await model.searchTask?.value
        XCTAssertEqual(model.visibleClips.map(\.id), [clip.id], "Leaving a preview must keep the open palette's search session active")
    }

}
