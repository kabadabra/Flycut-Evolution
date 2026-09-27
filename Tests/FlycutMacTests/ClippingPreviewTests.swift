import AppKit
import XCTest
import FlycutCore
@testable import FlycutMac

@MainActor final class ClippingPreviewTests: XCTestCase {
    private func clip(_ text: String, rtf: Data?) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "public.utf8-plain-text",
             sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil,
             collection: .recent, order: 0, formattedRTF: rtf)
    }

    func testRichPreviewContainsFullFormattedCopy() {
        let rtf = Data("{\\rtf1\\ansi\\b First\\b0\\par Second}".utf8)
        let value = clip("First\nSecond", rtf: rtf)
        let preview = ClippingPreviewContent.attributedText(for: value)
        XCTAssertEqual(preview?.string, "First\nSecond")
        let font = preview?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testOldOrMismatchedRichClipUsesCanonicalPlainText() {
        XCTAssertNil(ClippingPreviewContent.attributedText(for: clip("Old", rtf: nil)))
        XCTAssertNil(ClippingPreviewContent.attributedText(for: clip("Expected", rtf: Data("{\\rtf1\\ansi Other}".utf8))))
    }

    func testPreviewAcceptsEquivalentWindowsLineEndings() {
        let value = clip("First\r\nSecond", rtf: Data("{\\rtf1\\ansi First\\par Second}".utf8))
        XCTAssertEqual(ClippingPreviewContent.attributedText(for: value)?.string, "First\nSecond")
    }
}
