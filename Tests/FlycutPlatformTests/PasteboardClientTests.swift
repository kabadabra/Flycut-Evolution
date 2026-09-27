import XCTest
@testable import FlycutPlatform

final class PasteboardClientTests: XCTestCase {
    func testFailedTextReadNeedsConfirmedAccessDenial() {
        XCTAssertEqual(SystemPasteboardClient.classifyRead(nil, access: .unknown), .unavailable)
        XCTAssertEqual(SystemPasteboardClient.classifyRead(nil, access: .alwaysDeny), .denied)
        XCTAssertEqual(SystemPasteboardClient.classifyRead("available", access: .alwaysDeny), .text("available"))
    }
}
