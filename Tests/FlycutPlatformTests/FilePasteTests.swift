import XCTest
import AppKit
import FlycutCore
@testable import FlycutPlatform

@MainActor final class FilePasteTests: XCTestCase {
    func testMissingFileDoesNotReplaceClipboardWithFilename() async throws {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/missing.pdf")
        let clip = Clip(id: UUID(), text: "missing.pdf", pasteboardType: "public.file-url", sourceAppName: "Finder", sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, files: [try ClipFile(url: missing)])
        var writes = 0
        let client = PasteClient(write: { _ in writes += 1; return 1 }, changeCount: { 1 }, isTrusted: { true }, activate: { _ in true }, waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in false }, pasteKeyCode: { 9 }, sendPaste: { _ in true })
        let result = await PasteService(client: client, recordSelfWrite: { _ in }).copyOrPaste(clip, plain: false, mode: .copy, previousApp: nil)
        XCTAssertEqual(result, .clipboardUnavailable)
        XCTAssertEqual(writes, 0)
    }
    func testPlainCopyOfFileCopiesFullPath() async throws {
        let file = try ClipFile(url: URL(fileURLWithPath: "/tmp/folder/file.pdf"))
        let clip = Clip(id: UUID(), text: file.name, pasteboardType: "public.file-url", sourceAppName: nil, sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, files: [file])
        var text = ""
        let client = PasteClient(write: { text = $0; return 1 }, changeCount: { 1 }, isTrusted: { true }, activate: { _ in true }, waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in true }, pasteKeyCode: { 9 }, sendPaste: { _ in true })
        let result = await PasteService(client: client, recordSelfWrite: { _ in }).copyOrPaste(clip, plain: true, mode: .copy, previousApp: nil)
        XCTAssertEqual(result, .copied)
        XCTAssertEqual(text, file.path)
    }
    func testFilePasteWritesURLsAndUsesStandardPasteInFinder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("one.txt"), directory.appendingPathComponent("two.pdf")]
        for url in urls { try Data("fixture".utf8).write(to: url) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clip = Clip(id: UUID(), text: "one.txt\ntwo.pdf", pasteboardType: "public.file-url", sourceAppName: "Finder", sourceBundleURL: nil, capturedAt: nil, collection: .recent, order: 0, files: try urls.map { try ClipFile(url: $0) })
        var pasted = false, recorded: Int?
        let client = PasteClient(write: { _ in XCTFail("File used text write"); return nil }, changeCount: { board.changeCount }, isTrusted: { true }, activate: { _ in true }, waitForFocus: {}, isFrontmost: { _ in true }, isEditableTarget: { _ in XCTFail("Finder does not require a text editor"); return false }, pasteKeyCode: { 9 }, sendPaste: { _ in pasted = true; return true }, writeFiles: { PasteClient.writeFileURLs($0, to: board) })
        let result = await PasteService(client: client, recordSelfWrite: { recorded = $0 }).copyOrPaste(clip, plain: false, mode: .paste, previousApp: 123)
        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(pasted)
        XCTAssertEqual(recorded, board.changeCount)
        XCTAssertEqual(SystemPasteboardClient(pasteboard: board).readFileURLs(), .urls(urls))
        XCTAssertFalse((board.types ?? []).contains(.string), "File paste must not offer a filename as text")
    }

}
