import XCTest
import FlycutCore
import FlycutPlatform
@testable import FlycutMac
private actor RecognizerGate: ImageTextRecognizing {
    var active = 0; var maximum = 0
    var pending: [CheckedContinuation<String, any Error>] = []
    func recognize(_ png: Data) async throws -> String {
        active += 1; maximum = max(maximum, active)
        let result = try await withCheckedThrowingContinuation { pending.append($0) }
        active -= 1
        return result
    }
    func finish() { if !pending.isEmpty { pending.removeFirst().resume(returning: "Recognized") } }
}
@MainActor final class ImageRecognitionCoordinatorTests: XCTestCase {
    func testSerialQueueAndCancelledResultsDoNotApply() async throws {
        let recognizer = RecognizerGate()
        var results: [UUID] = []
        let coordinator = ImageRecognitionCoordinator(read: { _ in Data([1]) }, recognizer: recognizer, apply: { id, _, _, _ in results.append(id) })
        let a = imageClip("a"), b = imageClip("b")
        coordinator.enqueue(a); coordinator.enqueue(b)
        for _ in 0..<30 { if await recognizer.active == 1 { break }; await Task.yield() }
        coordinator.cancel(id: a.id)
        await recognizer.finish()
        for _ in 0..<30 { await Task.yield() }
        await recognizer.finish()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(results.contains(a.id))
        let maximum = await recognizer.maximum
        XCTAssertEqual(maximum, 1)
    }
    func testExcludingAnActiveSourcePermanentlyInvalidatesItsResult() async {
        let recognizer = RecognizerGate()
        var applied = false
        let coordinator = ImageRecognitionCoordinator(read: { _ in Data([1]) }, recognizer: recognizer, apply: { _, _, _, _ in applied = true })
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "a", width: 1, height: 1, byteCount: 1), sourceBundleIdentifier: "private.app")
        coordinator.enqueue(clip)
        for _ in 0..<100 { if await recognizer.active == 1 { break }; await Task.yield() }
        coordinator.invalidateDisallowedSources(["private.app"])
        await recognizer.finish()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(applied)
    }
    func testPausedQueueDoesNotStartAndDisabledQueueDiscards() async {
        let recognizer = RecognizerGate()
        let coordinator = ImageRecognitionCoordinator(read: { _ in Data([1]) }, recognizer: recognizer, apply: { _, _, _, _ in XCTFail("Disabled work applied") })
        coordinator.setPaused(true); coordinator.enqueue(imageClip("a"))
        for _ in 0..<10 { await Task.yield() }
        let active = await recognizer.active
        XCTAssertEqual(active, 0)
        coordinator.setEnabled(false); coordinator.setPaused(false)
        for _ in 0..<10 { await Task.yield() }
        let final = await recognizer.active
        XCTAssertEqual(final, 0)
    }
    private func imageClip(_ hash: String) -> Clip {
        .init(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: hash, width: 1, height: 1, byteCount: 1))
    }
}
