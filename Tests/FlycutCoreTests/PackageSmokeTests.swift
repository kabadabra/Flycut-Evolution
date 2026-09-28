import XCTest
import FlycutCore

final class PackageSmokeTests: XCTestCase {
    func testClipValueAndPackageVersion() {
        let clip = Clip(
            id: UUID(uuidString: "D95486F6-EF25-4DCF-BC5A-1A39E4B28238")!,
            text: "exact text\n",
            pasteboardType: "public.utf8-plain-text",
            sourceAppName: nil,
            sourceBundleURL: nil,
            capturedAt: nil,
            collection: .recent,
            order: 3
        )

        XCTAssertEqual(clip.text, "exact text\n")
        XCTAssertEqual(clip.collection, .recent)
        XCTAssertEqual(clip.order, 3)
        XCTAssertEqual(FlycutVersion.current, "1.0.1")
    }

    func testFavoriteClipKeepsItsCollectionAndOrder() {
        let clip = Clip(
            id: UUID(uuidString: "3DD23A8D-8D27-43AE-A9D7-0B0E08AB6E1C")!,
            text: "favorite",
            pasteboardType: "public.utf8-plain-text",
            sourceAppName: nil,
            sourceBundleURL: nil,
            capturedAt: nil,
            collection: .favorite,
            order: 7
        )

        XCTAssertEqual(clip.collection, .favorite)
        XCTAssertEqual(clip.order, 7)
    }
}
