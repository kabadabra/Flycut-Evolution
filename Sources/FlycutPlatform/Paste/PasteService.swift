import AppKit
import OSLog
import FlycutCore

public enum PasteMode: Sendable { case copy, paste }
public enum PasteResult: Equatable, Sendable {
    case copied, pasted, copiedNeedsAccessibility, copiedNoEditableTarget, copiedPasteUnavailable, writeFailed
    case pasteNeedsAccessibility, clipboardDenied, clipboardUnavailable, clipboardChanged
    case pasteUnavailable, noEditableTarget
}

/// All system effects are injected. A successful write returns the final change count.
@MainActor public struct PasteClient {
    public var write: (String) -> Int?
    public var writeImage: (Data) -> Int?
    public var writeFiles: ([URL]) -> Int?
    public var writeFormatted: (String, Data) -> Int?
    public var changeCount: () -> Int
    public var isTrusted: () -> Bool
    public var activate: (pid_t) -> Bool
    public var waitForFocus: () async -> Void
    public var isFrontmost: (pid_t) -> Bool
    public var isEditableTarget: (pid_t) -> Bool
    public var focusComposer: (pid_t) -> Bool
    public var pasteKeyCode: () -> UInt16?
    public var sendPaste: (UInt16) -> Bool
    public var sendPlainText: (String, pid_t) -> Bool

    public init(write: @escaping (String) -> Int?, changeCount: @escaping () -> Int, isTrusted: @escaping () -> Bool,
                activate: @escaping (pid_t) -> Bool, waitForFocus: @escaping () async -> Void,
                isFrontmost: @escaping (pid_t) -> Bool, isEditableTarget: @escaping (pid_t) -> Bool,
                focusComposer: @escaping (pid_t) -> Bool = { _ in false },
                pasteKeyCode: @escaping () -> UInt16?,
                sendPaste: @escaping (UInt16) -> Bool,
                sendPlainText: @escaping (String, pid_t) -> Bool = { _, _ in false },
                writeFormatted: ((String, Data) -> Int?)? = nil,
                writeImage: @escaping (Data) -> Int? = { _ in nil },
                writeFiles: @escaping ([URL]) -> Int? = { _ in nil }) {
        self.writeImage = writeImage; self.writeFiles = writeFiles
        self.write = write; self.changeCount = changeCount; self.isTrusted = isTrusted; self.activate = activate
        self.writeFormatted = writeFormatted ?? { text, _ in write(text) }
        self.waitForFocus = waitForFocus; self.isFrontmost = isFrontmost; self.isEditableTarget = isEditableTarget
        self.focusComposer = focusComposer
        self.pasteKeyCode = pasteKeyCode; self.sendPaste = sendPaste; self.sendPlainText = sendPlainText
    }

    public static var system: PasteClient {
        PasteClient(write: { text in
            let board = NSPasteboard.general
            board.clearContents()
            guard board.setString(text, forType: .string) else { return nil }
            return board.changeCount
        }, changeCount: { NSPasteboard.general.changeCount }, isTrusted: { AXIsProcessTrusted() }, activate: { pid in
            guard pid != ProcessInfo.processInfo.processIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.activate(options: [.activateIgnoringOtherApps])
        }, waitForFocus: {
            try? await Task.sleep(for: .milliseconds(150))
        }, isFrontmost: { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0 },
        isEditableTarget: { FocusedEditableTarget.isEditable(processID: $0) },
        focusComposer: { pid in
            guard FocusedEditableTarget.hasTeamsComposer(processID: pid),
                  let code = KeyboardLayout().keyCode(for: "r") else { return false }
            return postCommand(code)
        }, pasteKeyCode: { KeyboardLayout().keyCode(for: "v") }, sendPaste: { postCommand($0) },
        sendPlainText: { text, pid in
            FocusedEditableTarget.insertPlainText(text, processID: pid)
        }, writeFormatted: { text, rtf in
            let board = NSPasteboard.general
            board.clearContents()
            guard board.setString(text, forType: .string) else { return nil }
            _ = board.setData(rtf, forType: .rtf)
            return board.changeCount
        }, writeImage: { data in
            let board = NSPasteboard.general
            board.clearContents()
            guard board.setData(data, forType: .png) else { return nil }
            return board.changeCount
        }, writeFiles: { urls in
            writeFileURLs(urls, to: .general)
        })
    }

    static func writeFileURLs(_ urls: [URL], to board: NSPasteboard) -> Int? {
        guard !urls.isEmpty, urls.count <= 100, urls.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        board.clearContents()
        guard board.writeObjects(urls.map { $0 as NSURL }) else { return nil }
        return board.changeCount
    }

    private static func postCommand(_ code: UInt16) -> Bool {
        Logger(subsystem: "com.edynamics.flycut", category: "PlainPaste").notice("Posting command; key=\(code) modifiers=\(CGEventSource.flagsState(.combinedSessionState).rawValue)")
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor public final class PasteService {
    private let client: PasteClient
    private let pasteboard: any PasteboardClient
    private let recordSelfWrite: (Int) -> Void
    private var generation = 0

    public init(client: PasteClient = .system, pasteboard: any PasteboardClient = SystemPasteboardClient(), recordSelfWrite: @escaping (Int) -> Void) {
        self.client = client; self.pasteboard = pasteboard; self.recordSelfWrite = recordSelfWrite
    }

    public func pasteCurrentClipboardAsPlainText(previousApp: pid_t?) async -> PasteResult {
        generation += 1
        let request = generation
        guard client.isTrusted() else { return .pasteNeedsAccessibility }
        let sourceCount = pasteboard.changeCount
        let text: String
        switch pasteboard.readPlainText() {
        case .text(let value) where !value.isEmpty: text = value
        case .text, .unavailable: return .clipboardUnavailable
        case .denied: return .clipboardDenied
        }
        guard pasteboard.changeCount == sourceCount else { return .clipboardChanged }
        guard let pid = previousApp, client.activate(pid) else { return .pasteUnavailable }
        await client.waitForFocus()
        guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
              pasteboard.changeCount == sourceCount else { return .pasteUnavailable }
        guard client.isTrusted() else { return .pasteNeedsAccessibility }
        // Always use the editor's normal Paste command. Teams can accept an
        // AXSelectedText setter without changing its web editor, so AX success
        // cannot establish that text was inserted.
        guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
              pasteboard.changeCount == sourceCount else { return .pasteUnavailable }
        guard client.isTrusted() else { return .pasteNeedsAccessibility }
        guard let code = client.pasteKeyCode() else { return .pasteUnavailable }
        guard let count = client.write(text) else { return .writeFailed }
        recordSelfWrite(count)
        guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
              client.changeCount() == count else { return .pasteUnavailable }
        guard client.isTrusted() else { return .pasteNeedsAccessibility }
        return client.sendPaste(code) ? .pasted : .pasteUnavailable
    }

    public func copyOrPaste(_ text: String, mode: PasteMode, previousApp: pid_t?) async -> PasteResult {
        await copyOrPaste(text, formattedRTF: nil, mode: mode, previousApp: previousApp)
    }

    public func copyOrPaste(_ clip: Clip, plain: Bool, mode: PasteMode, previousApp: pid_t?) async -> PasteResult {
        if let image = clip.image {
            guard plain, let text = image.recognizedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .clipboardUnavailable }
            return await copyOrPaste(text, mode: mode, previousApp: previousApp)
        }
        if let files = clip.files, !files.isEmpty {
            if plain { return await copyOrPaste(files.map(\.path).joined(separator: "\n"), mode: mode, previousApp: previousApp) }
            let urls = files.map(\.url)
            guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return .clipboardUnavailable }
            generation += 1
            let request = generation
            guard let count = client.writeFiles(urls) else { return .writeFailed }
            return await finishPaste(count: count, mode: mode, previousApp: previousApp, request: request, requiresEditableTarget: false)
        }
        return await copyOrPaste(clip.text, formattedRTF: plain ? nil : clip.formattedRTF, mode: mode, previousApp: previousApp)
    }

    private func copyOrPaste(_ text: String, formattedRTF: Data?, mode: PasteMode, previousApp: pid_t?) async -> PasteResult {
        generation += 1
        let request = generation
        let count = formattedRTF.map { client.writeFormatted(text, $0) } ?? client.write(text)
        guard let count else { return .writeFailed }
        return await finishPaste(count: count, mode: mode, previousApp: previousApp, request: request)
    }
    public func copyOrPasteImage(_ png: Data, mode: PasteMode, previousApp: pid_t?) async -> PasteResult {
        generation += 1
        let request = generation
        guard let count = client.writeImage(png) else { return .writeFailed }
        return await finishPaste(count: count, mode: mode, previousApp: previousApp, request: request)
    }
    private func finishPaste(count: Int, mode: PasteMode, previousApp: pid_t?, request: Int, requiresEditableTarget: Bool = true) async -> PasteResult {
        // Must precede any suspension: the clipboard monitor can poll during focus restoration.
        recordSelfWrite(count)
        guard mode == .paste else { return .copied }
        guard client.isTrusted() else { return .copiedNeedsAccessibility }
        guard let pid = previousApp, client.activate(pid) else {
            return .copiedPasteUnavailable
        }
        await client.waitForFocus()
        guard !Task.isCancelled, request == generation, client.isFrontmost(pid) else { return .copiedPasteUnavailable }
        guard client.isTrusted() else { return .copiedNeedsAccessibility }
        guard let code = client.pasteKeyCode() else { return .copiedPasteUnavailable }
        // Another process can replace the shared clipboard while focus is settling.
        guard client.changeCount() == count else { return .copiedPasteUnavailable }
        if !requiresEditableTarget {
            guard !Task.isCancelled, request == generation, client.isFrontmost(pid), client.changeCount() == count, client.isTrusted() else { return .copiedPasteUnavailable }
            return client.sendPaste(code) ? .pasted : .copiedPasteUnavailable
        }
        var editable = false
        for attempt in 0..<3 {
            guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
                  client.changeCount() == count else { return .copiedPasteUnavailable }
            if client.isEditableTarget(pid) { editable = true; break }
            if attempt < 2 { await client.waitForFocus() }
        }
        if !editable, client.focusComposer(pid) {
            await client.waitForFocus()
            guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
                  client.changeCount() == count else { return .copiedPasteUnavailable }
            editable = client.isEditableTarget(pid)
        }
        guard editable else { return .copiedNoEditableTarget }
        // The Accessibility query crosses a process boundary; focus and clipboard can change while it runs.
        guard !Task.isCancelled, request == generation, client.isFrontmost(pid),
              client.changeCount() == count else { return .copiedPasteUnavailable }
        guard client.isTrusted() else { return .copiedNeedsAccessibility }
        return client.sendPaste(code) ? .pasted : .copiedPasteUnavailable
    }
}
