import Foundation
import XCTest
@testable import FlycutCore
@testable import FlycutPlatform

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testLaunchPreservesClipboardAndOneEventPerCount() {
        let board = FakePasteboard(count: 7, result: .text("old"))
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        XCTAssertEqual(board.readCount, 0)
        monitor.pollOnce()
        XCTAssertTrue(sink.clips.isEmpty)
        board.changeCount = 8
        board.result = .text("new")
        monitor.pollOnce()
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 1)
        XCTAssertEqual(sink.clips.map(\.text), ["new"])
        XCTAssertEqual(sink.clips.first?.sourceAppName, "Source")
        XCTAssertEqual(sink.clips.first?.sourceBundleURL, "file:///Applications/Source.app")
        XCTAssertEqual(sink.clips.first?.capturedAt, Date(timeIntervalSince1970: 100))
    }

    func testDelayedProviderChangeIsDiscarded() {
        let board = FakePasteboard(count: 1, result: .text("stale"))
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2
        board.onRead = { board.changeCount = 3 }
        monitor.pollOnce()
        XCTAssertTrue(sink.clips.isEmpty)
        board.onRead = nil
        board.result = .text("fresh")
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["fresh"])
    }

    func testOwnWriteIsSuppressedButSubsequentCopyIsCaptured() {
        let board = FakePasteboard(count: 1, result: .text("own"))
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2
        monitor.recordSelfWrite(changeCount: 2)
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)
        board.changeCount = 3
        board.result = .text("other")
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["other"])
    }

    func testDeniedReadDoesNotEmitClipAndReportsDenial() {
        let board = FakePasteboard(count: 1, result: .denied)
        let sink = ClipSink()
        var denied = 0
        let monitor = makeMonitor(board: board, sink: sink, onDenied: { denied += 1 })
        board.changeCount = 2
        monitor.pollOnce()
        monitor.pollOnce()
        XCTAssertTrue(sink.clips.isEmpty)
        XCTAssertEqual(denied, 1)
        XCTAssertEqual(board.readCount, 1)
    }

    func testRepeatOfTopTextIsCapturedWithSourceMetadata() {
        let board = FakePasteboard(count: 1, result: .text("same"))
        let sink = ClipSink()
        var metadataCalls = 0
        let monitor = ClipboardMonitor(
            pasteboard: board,
            settings: { FlycutSettings() },
            source: { metadataCalls += 1; return ClipboardSource(appName: "Source", bundleURL: nil) },
            now: { Date(timeIntervalSince1970: 100) },
            onClip: { sink.clips.append($0) }
        )
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["same"])
        XCTAssertEqual(metadataCalls, 1)
    }

    func testCapturesMatchingRTFAlongsideCanonicalPlainText() {
        let board = FakePasteboard(count: 1, result: .text("Rich"))
        board.advertisedTypes = ["public.utf8-plain-text", "public.rtf"]
        let rtf = Data("{\\rtf1\\ansi\\b Rich\\b0}".utf8)
        board.rtf = rtf
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.first?.text, "Rich")
        XCTAssertEqual(sink.clips.first?.formattedRTF, rtf)
        XCTAssertEqual(board.rtfReadCount, 1)
    }

    func testMalformedOrOversizedRTFFallsBackToPlainClip() {
        for rtf in [Data("not rtf".utf8), Data(repeating: 0x41, count: 262_145)] {
            let board = FakePasteboard(count: 1, result: .text("Safe"))
            board.advertisedTypes = ["public.utf8-plain-text", "public.rtf"]
            board.rtf = rtf
            let sink = ClipSink()
            let monitor = makeMonitor(board: board, sink: sink)
            board.changeCount = 2
            monitor.pollOnce()
            XCTAssertEqual(sink.clips.first?.text, "Safe")
            XCTAssertNil(sink.clips.first?.formattedRTF)
        }
    }

    func testRTFWithDifferentTextCannotReplaceCanonicalPlainText() {
        let board = FakePasteboard(count: 1, result: .text("Expected"))
        board.advertisedTypes = ["public.utf8-plain-text", "public.rtf"]
        board.rtf = Data("{\\rtf1\\ansi Other}".utf8)
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertNil(sink.clips.first?.formattedRTF)
    }

    func testResumeDiscardsCopyMadeWhilePausedBeforeNextPoll() {
        let board = FakePasteboard(count: 1, result: .text("paused copy"))
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        monitor.isPaused = true
        board.changeCount = 2
        monitor.isPaused = false
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)
        XCTAssertTrue(sink.clips.isEmpty)

        board.changeCount = 3
        board.result = .text("after resume")
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["after resume"])
    }

    func testPausedPollDiscardsCopyAndLaterCopyIsCaptured() {
        let board = FakePasteboard(count: 1, result: .text("paused copy"))
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        monitor.isPaused = true
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)
        monitor.isPaused = false
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)

        board.changeCount = 3
        board.result = .text("later copy")
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["later copy"])
    }

    func testSensitiveTypesAreBlockedBeforePayloadRead() {
        let board = FakePasteboard(count: 1, result: .text("private"))
        board.advertisedTypes = ["org.nspasteboard.ConcealedType", "public.rtf"]
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)
        XCTAssertEqual(board.rtfReadCount, 0)
        XCTAssertTrue(sink.clips.isEmpty)
    }

    func testExcludedAppIsBlockedBeforePayloadRead() {
        let board = FakePasteboard(count: 1, result: .text("private"))
        var settings = FlycutSettings()
        settings.excludedApplications = [.init(bundleIdentifier: "example.private", displayName: "Private")]
        let sink = ClipSink()
        let monitor = ClipboardMonitor(pasteboard: board, settings: { settings },
            source: { .init(appName: "Private", bundleURL: nil, bundleIdentifier: "example.private") },
            onClip: { sink.clips.append($0) })
        board.changeCount = 2
        monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0)
        XCTAssertTrue(sink.clips.isEmpty)
    }

    func testExpirySkipsCopyBetweenPausedPolls() {
        let board = FakePasteboard(count: 1, result: .text("paused"))
        let sink = ClipSink()
        var time = Date(timeIntervalSince1970: 100)
        let monitor = ClipboardMonitor(pasteboard: board, settings: { FlycutSettings() }, now: { time }, onClip: { sink.clips.append($0) })
        monitor.pause(for: 300)
        board.changeCount = 2
        time = time.addingTimeInterval(300)
        monitor.pollOnce()
        XCTAssertFalse(monitor.isPaused)
        XCTAssertEqual(board.readCount, 0)
        board.changeCount = 3
        monitor.pollOnce()
        XCTAssertEqual(sink.clips.count, 1)
    }
    func testIgnoreNextExternalChangeIncludingUnsupportedPreservesOwnWrites() {
        let board = FakePasteboard(count: 1, result: .unavailable)
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        monitor.ignoreNextCopy()
        board.changeCount = 2; monitor.recordSelfWrite(changeCount: 2); monitor.pollOnce()
        XCTAssertTrue(monitor.captureState.ignoresNextCopy)
        board.changeCount = 3; monitor.pollOnce()
        XCTAssertFalse(monitor.captureState.ignoresNextCopy)
        XCTAssertEqual(board.readCount, 0)
        board.changeCount = 4; board.result = .text("fresh"); monitor.pollOnce()
        XCTAssertEqual(sink.clips.map(\.text), ["fresh"])
    }
    func testTimedExpiryWithoutClipboardChangeAndSettingEditsKeepsDeadline() {
        let board = FakePasteboard(count: 1, result: .text("old"))
        var time = Date(timeIntervalSince1970: 100)
        var settings = FlycutSettings()
        let monitor = ClipboardMonitor(pasteboard: board, settings: { settings }, now: { time }, onClip: { _ in XCTFail() })
        monitor.pause(for: 300)
        settings.showHoverPreview = false
        time = time.addingTimeInterval(299); monitor.pollOnce(); XCTAssertTrue(monitor.isPaused)
        time = time.addingTimeInterval(1); monitor.pollOnce(); XCTAssertFalse(monitor.isPaused)
        XCTAssertEqual(board.readCount, 0)
    }
    func testInvalidImageWithRealTextFallsBackWithoutLosingText() async {
        let board = FakePasteboard(count: 1, result: .text("valid text"))
        board.advertisedTypes = ["public.png", "public.utf8-plain-text"]
        board.imageResult = .data(Data([1,2,3]), type: "public.png")
        let sink = ClipSink()
        let monitor = makeMonitor(board: board, sink: sink)
        board.changeCount = 2; monitor.pollOnce()
        for _ in 0..<100 where sink.clips.isEmpty { try? await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(sink.clips.map(\.text), ["valid text"])
    }
    func testExcludedAndSensitiveImageObservationsReadNoFormats() {
        let board = FakePasteboard(count: 1, result: .text("private"))
        board.advertisedTypes = ["public.png", "org.nspasteboard.ConcealedType"]
        let sink = ClipSink(), monitor = makeMonitor(board: board, sink: ClipSink())
        board.changeCount = 2; monitor.pollOnce()
        XCTAssertEqual(board.readCount, 0); XCTAssertEqual(board.imageReadCount, 0); XCTAssertTrue(sink.clips.isEmpty)
    }
    private func makeMonitor(board: FakePasteboard, sink: ClipSink, onDenied: @escaping @MainActor () -> Void = {}) -> ClipboardMonitor {
        let monitor = ClipboardMonitor(
            pasteboard: board,
            settings: { FlycutSettings() },
            source: { ClipboardSource(appName: "Source", bundleURL: "file:///Applications/Source.app") },
            now: { Date(timeIntervalSince1970: 100) },
            onClip: { sink.clips.append($0) },
            onAccessDenied: onDenied
        )
        return monitor
    }
}

@MainActor private final class ClipSink { var clips: [Clip] = [] }

@MainActor private final class FakePasteboard: PasteboardClient {
    var changeCount: Int
    var advertisedTypes = ["public.utf8-plain-text"]
    var result: PasteboardReadResult
    var readCount = 0
    var onRead: (() -> Void)?
    var rtf: Data?
    var rtfReadCount = 0
    var imageResult: PasteboardImageReadResult = .unavailable
    var imageReadCount = 0
    func readImage() -> PasteboardImageReadResult { imageReadCount += 1; return imageResult }

    init(count: Int, result: PasteboardReadResult) {
        changeCount = count
        self.result = result
    }

    func readPlainText() -> PasteboardReadResult {
        readCount += 1
        onRead?()
        return result
    }

    func readRTF() -> Data? {
        rtfReadCount += 1
        return rtf
    }
}
