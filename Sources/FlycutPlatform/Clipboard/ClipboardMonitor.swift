import AppKit
import FlycutCore

public struct ClipboardSource: Equatable {
    public let appName: String?
    public let bundleURL: String?

    public init(appName: String?, bundleURL: String?) {
        self.appName = appName
        self.bundleURL = bundleURL
    }
}

/// Polls on the main actor so the count, read, and post-read count check are ordered.
@MainActor public final class ClipboardMonitor {
    private let pasteboard: any PasteboardClient
    private let settings: @MainActor () -> FlycutSettings
    private let source: @MainActor () -> ClipboardSource
    private let now: @MainActor () -> Date
    private let onClip: @MainActor (Clip) -> Void
    private let onAccessDenied: @MainActor () -> Void
    private var observedCount: Int
    private var selfWriteCount: Int?
    private var timer: Timer?

    public var isPaused = false {
        didSet {
            // A copy between paused polls still belongs to the paused interval.
            if oldValue && !isPaused { observedCount = pasteboard.changeCount }
        }
    }

    public init(
        pasteboard: any PasteboardClient = SystemPasteboardClient(),
        settings: @escaping @MainActor () -> FlycutSettings,
        source: @escaping @MainActor () -> ClipboardSource = {
            let app = NSWorkspace.shared.frontmostApplication
            return ClipboardSource(appName: app?.localizedName, bundleURL: app?.bundleURL?.absoluteString)
        },
        now: @escaping @MainActor () -> Date = Date.init,
        onClip: @escaping @MainActor (Clip) -> Void,
        onAccessDenied: @escaping @MainActor () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.source = source
        self.now = now
        self.onClip = onClip
        self.onAccessDenied = onAccessDenied
        observedCount = pasteboard.changeCount
    }

    isolated deinit { timer?.invalidate() }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollOnce() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call with the count returned immediately after PasteService writes text.
    public func recordSelfWrite(changeCount: Int) {
        selfWriteCount = changeCount
    }

    public func pollOnce() {
        let count = pasteboard.changeCount
        guard count != observedCount else { return }
        observedCount = count
        if selfWriteCount == count {
            selfWriteCount = nil
            return
        }
        guard !isPaused else { return }
        let types = pasteboard.advertisedTypes
        let read = pasteboard.readPlainText()
        switch read {
        case .denied:
            onAccessDenied()
        case .unavailable:
            break
        case .text(let text):
            guard CapturePolicy.accepts(text: text, advertisedTypes: types, settings: settings()) else { return }
            let rtf = types.contains(NSPasteboard.PasteboardType.rtf.rawValue)
                ? validatedRTF(pasteboard.readRTF(), matching: text) : nil
            guard pasteboard.changeCount == count else { return }
            let origin = source()
            let clip = Clip(
                id: UUID(), text: text, pasteboardType: "public.utf8-plain-text",
                sourceAppName: origin.appName, sourceBundleURL: origin.bundleURL,
                capturedAt: now(), collection: .recent, order: 0, formattedRTF: rtf
            )
            onClip(clip)
        }
    }

    private func validatedRTF(_ data: Data?, matching plainText: String) -> Data? {
        guard let data, !data.isEmpty, data.count <= 256 * 1024,
              let styled = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                   documentAttributes: nil),
              Self.normalizeLineEndings(styled.string) == Self.normalizeLineEndings(plainText) else { return nil }
        var hasAttachment = false
        styled.enumerateAttribute(.attachment, in: NSRange(location: 0, length: styled.length)) { value, _, stop in
            if value != nil { hasAttachment = true; stop.pointee = true }
        }
        return hasAttachment ? nil : data
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
