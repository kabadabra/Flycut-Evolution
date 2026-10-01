import XCTest
import FlycutCore
@testable import FlycutPlatform

@MainActor final class InteractionTests: XCTestCase {
    func testImagePasteUsesStandardPasteAndRecordsOwnWrite() async {
        var count = 1, recorded = 0, pasted = false, plain = false
        let client = PasteClient(write: { _ in XCTFail("Image used text write"); return nil }, changeCount: { count }, isTrusted: { true }, activate: { _ in true }, waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in true }, pasteKeyCode: { 9 }, sendPaste: { _ in pasted = true; return true }, sendPlainText: { _, _ in plain = true; return true }, writeImage: { bytes in XCTAssertEqual(bytes, Data([1])); count += 1; return count })
        let service = PasteService(client: client, recordSelfWrite: { recorded = $0 })
        let result = await service.copyOrPasteImage(Data([1]), mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted); XCTAssertTrue(pasted); XCTAssertFalse(plain); XCTAssertEqual(recorded, count)
    }
    func testImageWithoutRecognizedTextDoesNotOverwritePlainClipboard() async {
        let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, image: .init(assetHash: "one", width: 1, height: 1, byteCount: 1))
        let fixture = PasteFixture(trusted: true)
        let result = await fixture.service.copyOrPaste(clip, plain: true, mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .clipboardUnavailable)
    }
    func testCopyAndPasteSuppressMonitorCaptureEvenDuringFocusDelay() async {
        for mode in [PasteMode.copy, .paste] {
            let board = InteractionBoard()
            var captured = 0
            let monitor = ClipboardMonitor(pasteboard: board, settings: { FlycutSettings() }, onClip: { _ in captured += 1 })
            let client = PasteClient(write: { text in board.text = text; board.changeCount += 2; return board.changeCount },
                                     changeCount: { board.changeCount }, isTrusted: { true }, activate: { _ in true },
                                     waitForFocus: { monitor.pollOnce() }, isFrontmost: { _ in true },
                                     isEditableTarget: { _ in true }, pasteKeyCode: { 47 }, sendPaste: { _ in true })
            let service = PasteService(client: client, recordSelfWrite: { monitor.recordSelfWrite(changeCount: $0) })
            _ = await service.copyOrPaste("selected", mode: mode, previousApp: 123)
            monitor.pollOnce()
            XCTAssertEqual(captured, 0)
            board.text = "external"; board.changeCount += 1
            monitor.pollOnce()
            XCTAssertEqual(captured, 1)
        }
    }

    func testAccessibilityAndLoginAdaptersExposeStatusAndErrors() async {
        var opened: URL?
        var trusted = false
        let accessibility = AccessibilityService(trust: { _ in trusted }, open: { opened = $0; return true })
        XCTAssertFalse(accessibility.isTrusted)
        XCTAssertFalse(accessibility.requestPermission())
        trusted = true
        XCTAssertTrue(accessibility.isTrusted)
        XCTAssertTrue(accessibility.openSettings())
        XCTAssertTrue(opened?.absoluteString.contains("Privacy_Accessibility") == true)
        let login = LoginItemService(client: LoginItemClient(status: { .requiresApproval }, register: {}, unregister: {}))
        XCTAssertEqual(login.status, .requiresApproval)
        let status = await login.setEnabled(true)
        XCTAssertEqual(status, .requiresApproval)
        let failing = LoginItemService(client: LoginItemClient(status: { .notRegistered }, register: { throw HotkeyError.system(-50) }, unregister: {}))
        if case .error = await failing.setEnabled(true) {} else { XCTFail("Must expose registration failure") }
    }

    func testDefaultHotkeyAndUnregister() throws {
        let client = FakeHotkey()
        let service = HotkeyService(client: client)
        try service.register(FlycutSettings().hotkey)
        XCTAssertEqual(client.key, 9)
        XCTAssertEqual(client.modifiers, 768) // Carbon command + shift
        service.unregister()
        XCTAssertEqual(client.removals, 1)
    }

    func testHotkeyConflictAndError() {
        let client = FakeHotkey()
        let service = HotkeyService(client: client)
        client.status = -9878
        XCTAssertThrowsError(try service.register(FlycutSettings().hotkey)) { XCTAssertEqual($0 as? HotkeyError, .conflict) }
        client.status = -50
        XCTAssertThrowsError(try service.register(FlycutSettings().hotkey)) { XCTAssertEqual($0 as? HotkeyError, .system(-50)) }
    }

    func testCopyAndDeniedPasteRecordFinalCountWithoutEvents() async {
        for mode in [PasteMode.copy, .paste] {
            let fixture = PasteFixture(trusted: false)
            let result = await fixture.service.copyOrPaste("selected", mode: mode, previousApp: 123)
            XCTAssertEqual(result, mode == .copy ? .copied : .copiedNeedsAccessibility)
            XCTAssertEqual(fixture.actions, ["write", "record:2"])
        }
    }

    func testFormattedClipWritesRichAndPlainRepresentationsForNormalActivation() async {
        let clip = Clip(id: UUID(), text: "Styled", pasteboardType: "public.utf8-plain-text",
                        sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent,
                        order: 0, formattedRTF: Data("{\\rtf1\\ansi\\b Styled}".utf8))
        var plainWrites = 0
        var richWrites = 0
        let client = PasteClient(write: { _ in plainWrites += 1; return 3 }, changeCount: { 3 },
                                 isTrusted: { true }, activate: { _ in true }, waitForFocus: {},
                                 isFrontmost: { _ in true }, isEditableTarget: { _ in true },
                                 pasteKeyCode: { 47 }, sendPaste: { _ in true },
                                 writeFormatted: { text, rtf in
            XCTAssertEqual(text, clip.text)
            XCTAssertEqual(rtf, clip.formattedRTF)
            richWrites += 1
            return 3
        })
        var selfWrites: [Int] = []
        let service = PasteService(client: client, recordSelfWrite: { selfWrites.append($0) })
        let result = await service.copyOrPaste(clip, plain: false, mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(plainWrites, 0)
        XCTAssertEqual(richWrites, 1)
        XCTAssertEqual(selfWrites, [3])
    }

    func testPlainRowActionWritesOnlyPlainRepresentation() async {
        let clip = Clip(id: UUID(), text: "Styled", pasteboardType: "public.utf8-plain-text",
                        sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent,
                        order: 0, formattedRTF: Data("{\\rtf1\\ansi\\b Styled}".utf8))
        var plainWrites = 0
        let client = PasteClient(write: { text in XCTAssertEqual(text, "Styled"); plainWrites += 1; return 3 },
                                 changeCount: { 3 }, isTrusted: { true }, activate: { _ in true },
                                 waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in true },
                                 pasteKeyCode: { 47 }, sendPaste: { _ in true },
                                 writeFormatted: { _, _ in XCTFail("Plain action must omit RTF"); return nil })
        let service = PasteService(client: client, recordSelfWrite: { _ in })
        let result = await service.copyOrPaste(clip, plain: true, mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(plainWrites, 1)
    }

    func testNonQWERTYPasteRestoresFocusAndRecordsBeforeDelay() async {
        let fixture = PasteFixture(trusted: true)
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.actions, ["write", "record:2", "activate:123", "wait", "front:123", "front:123", "editable:123", "front:123", "key:47"])
    }

    func testPasteWaitsForDelayedWebComposerFocus() async {
        let fixture = PasteFixture(trusted: true)
        fixture.editable = false
        var waits = 0
        fixture.duringWait = {
            waits += 1
            if waits == 2 { fixture.editable = true }
        }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(waits, 2)
    }

    func testPlainShortcutUsesNormalPasteWhenAccessibilityClaimsInsertionSucceeded() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic Teams source")
        // Teams reports AX insertion success without updating its web editor.
        fixture.insertionSucceeds = true

        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.writtenText, "Synthetic Teams source")
        XCTAssertEqual(fixture.actions.filter { $0 == "key:47" }.count, 1)
        XCTAssertNil(fixture.insertedText)
        XCTAssertTrue(fixture.actions.contains("record:2"))
    }

    func testPlainShortcutPastesTheCurrentClipboardText() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic formatted source")
        fixture.pasteboard.changeCount = 8

        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.pasteboard.reads, 1)
        XCTAssertEqual(fixture.writtenText, "Synthetic formatted source")
        XCTAssertNil(fixture.insertedText)
        XCTAssertTrue(fixture.actions.contains("key:47"))
        XCTAssertEqual(fixture.pasteboard.changeCount, 8)
    }

    func testPlainShortcutUsesNormalPasteWhenEditorRejectsAccessibilityInsertion() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic fallback")
        fixture.insertionSucceeds = false
        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.writtenText, "Synthetic fallback")
        XCTAssertEqual(fixture.actions.filter { $0 == "key:47" }.count, 1)
        XCTAssertTrue(fixture.actions.contains("record:2"))
    }

    func testPlainShortcutWorksWhenEditorDoesNotExposeEditableAccessibilityRole() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic web editor")
        fixture.editable = false
        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.writtenText, "Synthetic web editor")
        XCTAssertTrue(fixture.actions.contains("key:47"))
        XCTAssertFalse(fixture.actions.contains("focusComposer:123"))
    }

    func testPlainShortcutDoesNotWriteOrPasteAfterDestinationOrClipboardChanges() async {
        for change in ["focus", "clipboard", "trust"] {
            let fixture = PasteFixture(trusted: true)
            fixture.pasteboard.result = .text("Synthetic fallback")
            fixture.insertionSucceeds = false
            fixture.duringWait = {
                switch change {
                case "focus": fixture.frontmost = false
                case "clipboard": fixture.pasteboard.changeCount += 1
                default: fixture.trusted = false
                }
            }
            let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)
            XCTAssertEqual(result, change == "trust" ? .pasteNeedsAccessibility : .pasteUnavailable)
            XCTAssertNil(fixture.writtenText)
            XCTAssertFalse(fixture.actions.contains("key:47"))
        }
    }

    func testPlainShortcutWithoutPasteKeyLeavesClipboardUntouched() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic fallback")
        fixture.insertionSucceeds = false
        fixture.key = nil
        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)
        XCTAssertEqual(result, .pasteUnavailable)
        XCTAssertNil(fixture.writtenText)
    }

    func testCancelledShortcutDoesNotInsertOrRewriteClipboard() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic cancelled")
        let gate = FocusGate()
        fixture.duringWait = { await gate.wait() }
        let task = Task { await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123) }
        await gate.waitUntilSuspended()
        task.cancel()
        gate.resume()
        let result = await task.value
        XCTAssertEqual(result, .pasteUnavailable)
        XCTAssertNil(fixture.insertedText)
        XCTAssertNil(fixture.writtenText)
    }

    func testPlainShortcutKeepsNewFormattedCopyInHistoryBeforeStrippingClipboard() async throws {
        let board = InteractionBoard()
        board.changeCount = 1
        var captured: [Clip] = []
        let monitor = ClipboardMonitor(pasteboard: board, settings: { FlycutSettings() },
                                       onClip: { captured.append($0) })
        board.text = "Synthetic new copy"
        board.rtf = try NSAttributedString(string: board.text, attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
            .data(from: NSRange(location: 0, length: board.text.utf16.count), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let originalRTF = board.rtf
        board.advertisedTypes.append("public.rtf")
        board.changeCount = 2
        // The shortcut coordinator captures the copy before requesting paste.
        monitor.pollOnce()
        let client = PasteClient(write: { text in
            board.text = text
            board.rtf = nil
            board.advertisedTypes = ["public.utf8-plain-text"]
            board.changeCount += 1
            return board.changeCount
        }, changeCount: { board.changeCount }, isTrusted: { true }, activate: { _ in true },
           waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in true },
           pasteKeyCode: { 9 }, sendPaste: { code in
            XCTAssertEqual(code, 9)
            XCTAssertEqual(board.text, "Synthetic new copy")
            XCTAssertNil(board.rtf)
            return true
        })
        let service = PasteService(client: client, pasteboard: board,
                                   recordSelfWrite: { monitor.recordSelfWrite(changeCount: $0) })

        let result = await service.pasteCurrentClipboardAsPlainText(previousApp: 123)
        XCTAssertEqual(result, .pasted)
        monitor.pollOnce()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.text, "Synthetic new copy")
        XCTAssertEqual(captured.first?.formattedRTF, originalRTF)
        XCTAssertEqual(board.changeCount, 3)
    }

    func testPlainShortcutDoesNotReadOrRewriteClipboardWithoutAccessibility() async {
        let fixture = PasteFixture(trusted: false)
        fixture.pasteboard.result = .text("Synthetic source")

        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)

        XCTAssertEqual(result, .pasteNeedsAccessibility)
        XCTAssertEqual(fixture.pasteboard.reads, 0)
        XCTAssertNil(fixture.writtenText)
    }

    func testPlainShortcutReportsDeniedOrUnavailableTextWithoutRewritingClipboard() async {
        for (read, expected) in [(PasteboardReadResult.denied, PasteResult.clipboardDenied),
                                 (.unavailable, .clipboardUnavailable), (.text(""), .clipboardUnavailable)] {
            let fixture = PasteFixture(trusted: true)
            fixture.pasteboard.result = read

            let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)

            XCTAssertEqual(result, expected)
            XCTAssertNil(fixture.writtenText)
        }
    }

    func testPlainShortcutLeavesChangedClipboardUntouched() async {
        let fixture = PasteFixture(trusted: true)
        fixture.pasteboard.result = .text("Synthetic old source")
        fixture.pasteboard.onRead = { fixture.pasteboard.changeCount += 1 }

        let result = await fixture.service.pasteCurrentClipboardAsPlainText(previousApp: 123)

        XCTAssertEqual(result, .clipboardChanged)
        XCTAssertNil(fixture.writtenText)
    }

    func testNoEditableFieldLeavesTextCopiedWithoutSendingPaste() async {
        let fixture = PasteFixture(trusted: true)
        fixture.editable = false
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedNoEditableTarget)
        XCTAssertTrue(fixture.actions.contains("editable:123"))
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
        XCTAssertEqual(fixture.actions.filter { $0 == "write" }.count, 1)
    }

    func testTeamsComposeShortcutRestoresEditableFocusBeforePaste() async {
        let fixture = PasteFixture(trusted: true)
        fixture.editable = false
        fixture.canFocusComposer = true
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(fixture.actions.filter { $0 == "focusComposer:123" }.count, 1)
        XCTAssertEqual(fixture.actions.last, "key:47")
    }

    func testTeamsComposeShortcutMustProduceEditableFocus() async {
        let fixture = PasteFixture(trusted: true)
        fixture.editable = false
        fixture.canFocusComposer = true
        fixture.focusComposerSucceeds = false
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedNoEditableTarget)
        XCTAssertFalse(fixture.actions.contains("key:47"))
    }

    func testFieldBecomingNoneditableDuringFocusWaitDoesNotPaste() async {
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = { fixture.editable = false }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedNoEditableTarget)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
    }

    func testFocusOrClipboardChangingDuringEditableCheckDoesNotPaste() async {
        for change in ["focus", "clipboard", "trust"] {
            let fixture = PasteFixture(trusted: true)
            fixture.duringEditableCheck = {
                switch change {
                case "focus": fixture.frontmost = false
                case "clipboard": fixture.count = 3
                default: fixture.trusted = false
                }
            }
            let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
            XCTAssertEqual(result, change == "trust" ? .copiedNeedsAccessibility : .copiedPasteUnavailable,
                           "\(change) changed during the Accessibility check")
            XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
        }
    }

    func testLostFocusAndMissingLayoutDoNotSendEvents() async {
        let fixture = PasteFixture(trusted: true)
        fixture.frontmost = false
        let lost = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(lost, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains("key:47"))
        fixture.frontmost = true
        fixture.key = nil
        let missing = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(missing, .copiedPasteUnavailable)
    }

    func testClipboardReplacementDuringWaitDoesNotSendOrOverwrite() async {
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = { fixture.count = 3 }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
        XCTAssertEqual(fixture.actions.filter { $0 == "write" }.count, 1)
        XCTAssertEqual(fixture.count, 3)
    }

    func testTrustRevocationDuringWaitDoesNotSend() async {
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = { fixture.trusted = false }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedNeedsAccessibility)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
    }

    func testCancelledSuspendedPasteDoesNotSend() async {
        let fixture = PasteFixture(trusted: true)
        let gate = FocusGate()
        fixture.duringWait = { await gate.wait() }
        let task = Task { await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123) }
        await gate.waitUntilSuspended()
        task.cancel()
        gate.resume()
        let result = await task.value
        XCTAssertEqual(result, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
    }

    func testNewCopyInvalidatesSuspendedPaste() async {
        let fixture = PasteFixture(trusted: true)
        let gate = FocusGate()
        fixture.duringWait = { await gate.wait() }
        let task = Task { await fixture.service.copyOrPaste("first", mode: .paste, previousApp: 123) }
        await gate.waitUntilSuspended()
        _ = await fixture.service.copyOrPaste("second", mode: .copy, previousApp: nil)
        gate.resume()
        let result = await task.value
        XCTAssertEqual(result, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
    }

    func testStickyMousePasteUsesLatestExternalAppAndFreezesTargetDuringWait() async {
        var targets = PasteTargetHistory(ownProcessID: 99)
        targets.observeActivation(processID: 101) // App A before opening the palette.
        targets.observeActivation(processID: 99)  // Flycut becomes active.
        XCTAssertEqual(targets.previousExternalApp, 101)
        targets.observeActivation(processID: 202) // App B while sticky panel remains visible.
        targets.observeActivation(processID: 99)  // Mouse reactivates the existing palette.
        let frozenTarget = targets.previousExternalApp
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = {
            targets.observeActivation(processID: 303)
            fixture.frontmost = false
        }
        let result = await fixture.service.copyOrPaste("synthetic", mode: .paste, previousApp: frozenTarget)
        XCTAssertEqual(result, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
        XCTAssertTrue(fixture.actions.contains("activate:202"))
        XCTAssertTrue(fixture.actions.contains("front:202"))
        XCTAssertFalse(fixture.actions.contains("activate:101"))
        XCTAssertFalse(fixture.actions.contains("activate:303"))
        XCTAssertEqual(targets.previousExternalApp, 303, "A later action must use the newly observed external app")
    }

    func testOwnActivationAndUnknownForegroundDoNotEraseExternalTarget() {
        var targets = PasteTargetHistory(ownProcessID: 99)
        targets.observeActivation(processID: 99)
        XCTAssertNil(targets.previousExternalApp)
        targets.observeActivation(processID: 101)
        targets.observeActivation(processID: nil)
        targets.observeActivation(processID: 99)
        XCTAssertEqual(targets.previousExternalApp, 101)
    }

    func testLayoutIsResolvedAfterFocusChanges() async {
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = { fixture.key = 12 }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(fixture.actions.contains("key:12"))
        XCTAssertFalse(fixture.actions.contains("key:47"))
    }

    func testLayoutBecomingUnavailableDuringWaitDoesNotSend() async {
        let fixture = PasteFixture(trusted: true)
        fixture.duringWait = { fixture.key = nil }
        let result = await fixture.service.copyOrPaste("selected", mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .copiedPasteUnavailable)
        XCTAssertFalse(fixture.actions.contains(where: { $0.hasPrefix("key:") }))
    }

    func testLayoutMapsCharacterUsingInjectedTranslation() {
        let layout = KeyboardLayout { code in code == 47 ? "v" : "x" }
        XCTAssertEqual(layout.keyCode(for: "v"), 47)
        XCTAssertNil(layout.keyCode(for: "z"))
    }
}

@MainActor private final class FakeHotkey: HotkeyClient {
    var key: UInt32?; var modifiers: UInt32?; var removals = 0; var status: Int32 = 0
    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) -> Int32 {
        key = keyCode; self.modifiers = modifiers; return status
    }
    func unregister() { removals += 1 }
}

@MainActor private final class PasteFixture {
    var actions: [String] = []
    let pasteboard = ShortcutBoard()
    var writtenText: String?
    var insertedText: String?
    var insertionSucceeds = true
    var count = 2
    var frontmost = true
    var editable = true
    var canFocusComposer = false
    var focusComposerSucceeds = true
    var key: UInt16? = 47
    var trusted: Bool
    var duringWait: @MainActor () async -> Void = {}
    var duringEditableCheck: @MainActor () -> Void = {}
    init(trusted: Bool) { self.trusted = trusted }
    lazy var service = PasteService(client: PasteClient(
        write: { [unowned self] text in writtenText = text; actions.append("write"); return 2 },
        changeCount: { [unowned self] in count },
        isTrusted: { [unowned self] in trusted },
        activate: { [unowned self] pid in actions.append("activate:\(pid)"); return true },
        waitForFocus: { [unowned self] in actions.append("wait"); await duringWait() },
        isFrontmost: { [unowned self] pid in actions.append("front:\(pid)"); return frontmost },
        isEditableTarget: { [unowned self] pid in actions.append("editable:\(pid)"); duringEditableCheck(); return editable },
        focusComposer: { [unowned self] pid in
            actions.append("focusComposer:\(pid)")
            if canFocusComposer && focusComposerSucceeds { editable = true }
            return canFocusComposer
        },
        pasteKeyCode: { [unowned self] in key },
        sendPaste: { [unowned self] key in actions.append("key:\(key)"); return true },
        sendPlainText: { [unowned self] text, pid in insertedText = text; actions.append("insert:\(pid)"); return insertionSucceeds }
    ), pasteboard: pasteboard, recordSelfWrite: { [unowned self] count in actions.append("record:\(count)") })
}

@MainActor private final class ShortcutBoard: PasteboardClient {
    var changeCount = 0
    var advertisedTypes: [String] = []
    var result: PasteboardReadResult = .unavailable
    var reads = 0
    var onRead: @MainActor () -> Void = {}
    func readPlainText() -> PasteboardReadResult { reads += 1; onRead(); return result }
    func readRTF() -> Data? { nil }
}

@MainActor private final class InteractionBoard: PasteboardClient {
    var changeCount = 0
    var text = ""
    var advertisedTypes = ["public.utf8-plain-text"]
    func readPlainText() -> PasteboardReadResult { .text(text) }
    var rtf: Data?
    func readRTF() -> Data? { rtf }
}

@MainActor private final class FocusGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume(); observer = nil
        }
    }
    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
}
