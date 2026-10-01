import XCTest
@testable import FlycutCore
final class CaptureSessionStateTests: XCTestCase {
    func testExactDeadlinesAndManualResume() {
        for duration: Double in [300, 900, 3600] {
            var state = CaptureSessionState()
            let deadline = Date(timeIntervalSince1970: duration)
            state.setPause(.until(deadline))
            XCTAssertFalse(state.expire(at: deadline.addingTimeInterval(-1)))
            XCTAssertTrue(state.expire(at: deadline))
            XCTAssertEqual(state.pause, .running)
            state.setPause(.manual)
            XCTAssertFalse(state.expire(at: .distantFuture))
            state.resume()
            XCTAssertEqual(state.pause, .running)
        }
    }
    func testSinglePendingIgnoreCanBeCancelled() {
        var state = CaptureSessionState()
        state.ignoreNextCopy(); state.ignoreNextCopy()
        XCTAssertTrue(state.consumeExternalChange())
        XCTAssertFalse(state.consumeExternalChange())
        state.ignoreNextCopy(); state.cancelIgnore()
        XCTAssertFalse(state.consumeExternalChange())
    }
}
