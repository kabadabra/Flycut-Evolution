import AppKit
import FlycutCore

public struct ClipboardSource: Equatable {
    public let appName: String?
    public let bundleURL: String?
    public let bundleIdentifier: String?

    public init(appName: String?, bundleURL: String?, bundleIdentifier: String? = nil) {
        self.appName = appName
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
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
    private var imageTask: Task<Void, Never>?
    public var onImage: @MainActor (Clip, ImageAsset) -> Void = { _, _ in }
    public var onImageRejected: @MainActor () -> Void = {}

    public private(set) var captureState = CaptureSessionState()
    public var onStateChange: @MainActor (CaptureSessionState) -> Void = { _ in }
    public var isPaused: Bool {
        get { captureState.isPaused }
        set { if newValue { pause(for: nil) } else { resumeCapture() } }
    }
    public func pause(for duration: TimeInterval?) {
        imageTask?.cancel()
        captureState.setPause(duration.map { .until(now().addingTimeInterval($0)) } ?? .manual)
        onStateChange(captureState)
    }
    public func resumeCapture() {
        observedCount = pasteboard.changeCount
        captureState.resume(); onStateChange(captureState)
    }
    public func ignoreNextCopy() { captureState.ignoreNextCopy(); onStateChange(captureState) }
    public func cancelIgnoreNextCopy() { captureState.cancelIgnore(); onStateChange(captureState) }

    public init(
        pasteboard: any PasteboardClient = SystemPasteboardClient(),
        settings: @escaping @MainActor () -> FlycutSettings,
        source: @escaping @MainActor () -> ClipboardSource = {
            let app = NSWorkspace.shared.frontmostApplication
            return ClipboardSource(appName: app?.localizedName, bundleURL: app?.bundleURL?.absoluteString, bundleIdentifier: app?.bundleIdentifier)
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
        imageTask?.cancel()
        timer?.invalidate()
        timer = nil
    }

    /// Call with the count returned immediately after PasteService writes text.
    public func recordSelfWrite(changeCount: Int) {
        selfWriteCount = changeCount
    }

    public func pollOnce() {
        if captureState.expire(at: now()) {
            observedCount = pasteboard.changeCount
            onStateChange(captureState)
        }
        let count = pasteboard.changeCount
        guard count != observedCount else { return }
        observedCount = count
        imageTask?.cancel()
        if selfWriteCount == count {
            selfWriteCount = nil
            return
        }
        selfWriteCount = nil
        if captureState.consumeExternalChange() { onStateChange(captureState); return }
        guard !isPaused else { return }
        let types = pasteboard.advertisedTypes
        let origin = source()
        guard CapturePolicy.acceptsBeforeRead(advertisedTypes: types, sourceBundleIdentifier: origin.bundleIdentifier, settings: settings()) else { return }
        if types.contains("public.file-url") || types.contains("NSFilenamesPboardType") {
            switch pasteboard.readFileURLs() {
            case .denied: onAccessDenied(); return
            case .unavailable: break
            case .urls(let urls):
                guard pasteboard.changeCount == count, !urls.isEmpty, urls.count <= 100,
                      let files = try? urls.map({ try ClipFile(url: $0) }) else { return }
                let date = now()
                if urls.count == 1, settings().imageCaptureEnabled {
                    imageTask = Task { [weak self] in
                        guard let self, !Task.isCancelled, pasteboard.changeCount == count, !isPaused,
                              CapturePolicy.acceptsBeforeRead(advertisedTypes: types, sourceBundleIdentifier: origin.bundleIdentifier, settings: settings()) else { return }
                        guard settings().imageCaptureEnabled else { captureFiles(files, origin: origin, date: date); return }
                        let decoded = await Task.detached(priority: .utility) { try? ClipboardImageDecoder.decodeFile(urls[0]) }.value
                        guard !Task.isCancelled, pasteboard.changeCount == count, !isPaused,
                              CapturePolicy.acceptsBeforeRead(advertisedTypes: types, sourceBundleIdentifier: origin.bundleIdentifier, settings: settings()) else { return }
                        if let decoded, settings().imageCaptureEnabled {
                            let metadata = ClipImage(assetHash: decoded.asset.hash, width: decoded.width, height: decoded.height, byteCount: decoded.asset.png.count)
                            onImage(Clip(id: UUID(), text: files[0].name, pasteboardType: "public.png", sourceAppName: origin.appName, sourceBundleURL: origin.bundleURL, capturedAt: date, collection: .recent, order: 0, image: metadata, sourceBundleIdentifier: origin.bundleIdentifier, files: files), decoded.asset)
                        } else { captureFiles(files, origin: origin, date: date) }
                    }
                } else { captureFiles(files, origin: origin, date: date) }
                return
            }
        }
        let read = pasteboard.readPlainText()
        if case .denied = read { onAccessDenied(); return }
        if settings().imageCaptureEnabled, types.contains(where: ClipboardImageDecoder.types.contains) {
            switch pasteboard.readImage() {
            case .denied: onAccessDenied(); return
            case .unavailable: break
            case .data(let data, let type):
                guard pasteboard.changeCount == count else { return }
                let accompanying: String?
                if case .text(let text) = read, !text.isEmpty {
                    guard CapturePolicy.accepts(text: text, advertisedTypes: types, settings: settings()) else { return }
                    accompanying = text
                } else { accompanying = nil }
                let date = now()
                imageTask = Task { [weak self] in
                    let decoded = await Task.detached(priority: .utility) { try? ClipboardImageDecoder.decode(data, type: type) }.value
                    guard let self, !Task.isCancelled, pasteboard.changeCount == count, !isPaused,
                          settings().imageCaptureEnabled,
                          CapturePolicy.acceptsBeforeRead(advertisedTypes: types, sourceBundleIdentifier: origin.bundleIdentifier, settings: settings()) else { return }
                    guard let decoded else {
                        onImageRejected()
                        if let accompanying { captureText(accompanying, types: types, origin: origin, count: count) }
                        return
                    }
                    let metadata = ClipImage(assetHash: decoded.asset.hash, width: decoded.width, height: decoded.height, byteCount: decoded.asset.png.count, accompanyingText: accompanying)
                    let clip = Clip(id: UUID(), text: "", pasteboardType: "public.png", sourceAppName: origin.appName, sourceBundleURL: origin.bundleURL, capturedAt: date, collection: .recent, order: 0, image: metadata, sourceBundleIdentifier: origin.bundleIdentifier)
                    onImage(clip, decoded.asset)
                }
                return
            }
        }
        switch read {
        case .denied:
            onAccessDenied()
        case .unavailable:
            break
        case .text(let text): captureText(text, types: types, origin: origin, count: count)
        }
    }
    private func captureFiles(_ files: [ClipFile], origin: ClipboardSource, date: Date) {
        onClip(Clip(id: UUID(), text: files.map(\.name).joined(separator: "\n"), pasteboardType: "public.file-url", sourceAppName: origin.appName, sourceBundleURL: origin.bundleURL, capturedAt: date, collection: .recent, order: 0, sourceBundleIdentifier: origin.bundleIdentifier, files: files))
    }
    private func captureText(_ text: String, types: [String], origin: ClipboardSource, count: Int) {
        guard CapturePolicy.accepts(text: text, advertisedTypes: types, settings: settings()) else { return }
        let rtf = types.contains(NSPasteboard.PasteboardType.rtf.rawValue) ? validatedRTF(pasteboard.readRTF(), matching: text) : nil
        guard pasteboard.changeCount == count else { return }
        onClip(Clip(id: UUID(), text: text, pasteboardType: "public.utf8-plain-text", sourceAppName: origin.appName, sourceBundleURL: origin.bundleURL, capturedAt: now(), collection: .recent, order: 0, formattedRTF: rtf, sourceBundleIdentifier: origin.bundleIdentifier))
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
