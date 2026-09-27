import Foundation
import XCTest
@testable import FlycutCore

final class PalettePreviewTests: XCTestCase {
    private func clip(_ text: String) -> Clip {
        Clip(id: UUID(), text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: nil,
             sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0)
    }

    func testPreviewLineCollapsesFormattingWhitespaceWithoutChangingClip() {
        let original = "  This  is\nmy\tformatted\r\n text  "
        let value = clip(original)
        XCTAssertEqual(value.previewLine(limit: 40), "This is my formatted text")
        XCTAssertEqual(value.text, original)
    }

    func testPreviewLineTruncatesByCharacterAndAddsEllipsisOnlyWhenNeeded() {
        let value = clip("👩🏽‍💻 café extra")
        XCTAssertEqual(value.previewLine(limit: 6), "👩🏽‍💻 café…")
        XCTAssertEqual(clip("Short").previewLine(limit: 5), "Short")
        XCTAssertEqual(clip("Short  ").previewLine(limit: 5), "Short")
    }

    func testPreFormattingClipJSONStillDecodesAsPlain() throws {
        let oldJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","text":"Earlier copy","pasteboardType":"public.utf8-plain-text","collection":"recent","order":0}
        """
        let value = try JSONDecoder().decode(Clip.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(value.text, "Earlier copy")
        XCTAssertNil(value.formattedRTF)
    }
}
