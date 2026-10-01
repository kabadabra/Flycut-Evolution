import Foundation
import FlycutCore
import FlycutPlatform

@MainActor final class ImageRecognitionCoordinator {
    private let read: @Sendable (String) async throws -> Data?
    private let recognizer: any ImageTextRecognizing
    private let apply: @MainActor (UUID, String, String?, ImageRecognitionState) async -> Void
    private let eligible: @MainActor (Clip) -> Bool
    private var queue: [(Clip, UUID)] = []
    private var tokens: [UUID: UUID] = [:]
    private var activeClip: Clip?
    private var running = false
    private var paused = false
    private var enabled = true
    init(read: @escaping @Sendable (String) async throws -> Data?, recognizer: any ImageTextRecognizing = ImageTextRecognizer(), eligible: @escaping @MainActor (Clip) -> Bool = { _ in true }, apply: @escaping @MainActor (UUID, String, String?, ImageRecognitionState) async -> Void) {
        self.read = read; self.recognizer = recognizer; self.eligible = eligible; self.apply = apply
    }
    func enqueue(_ clip: Clip) {
        guard enabled, clip.image != nil, tokens[clip.id] == nil, eligible(clip) else { return }
        let token = UUID(); tokens[clip.id] = token; queue.append((clip, token)); startNext()
    }
    func cancel(id: UUID) { tokens[id] = nil; queue.removeAll { $0.0.id == id } }
    func setPaused(_ paused: Bool) { self.paused = paused; startNext() }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled; if !enabled { tokens.removeAll(); queue.removeAll() }; startNext() }
    func invalidateDisallowedSources(_ excluded: Set<String>) {
        for (clip, _) in queue where clip.sourceBundleIdentifier.map(excluded.contains) == true { cancel(id: clip.id) }
        if let activeClip, activeClip.sourceBundleIdentifier.map(excluded.contains) == true { cancel(id: activeClip.id) }
    }
    private func startNext() {
        guard !running, !paused, enabled else { return }
        while !queue.isEmpty {
            let (clip, token) = queue.removeFirst()
            guard let image = clip.image, tokens[clip.id] == token, eligible(clip) else { tokens[clip.id] = nil; continue }
            running = true; activeClip = clip
            Task { [self] in
                var text: String?, state: ImageRecognitionState = .failed
                do {
                    if let png = try await read(image.assetHash) {
                        text = try await recognizer.recognize(png)
                        state = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? .recognized : .noText
                    }
                } catch { state = .failed }
                if enabled, tokens[clip.id] == token, eligible(clip) { await apply(clip.id, image.assetHash, text, state) }
                if tokens[clip.id] == token { tokens[clip.id] = nil }
                running = false; activeClip = nil; startNext()
            }
            return
        }
    }
}
