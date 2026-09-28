import Foundation
import Darwin

public actor HistoryService {
    private struct DuplicateKey: Hashable {
        let text: String
        let source: String

        init(_ clip: Clip) {
            text = clip.text
            if let name = clip.sourceAppName { source = "name:\(name)" }
            else if let url = clip.sourceBundleURL { source = "url:\(url)" }
            else { source = "unknown" }
        }
    }
    private let repository: any HistoryRepository
    private let recentCapacity: Int
    private let favoriteCapacity: Int
    private let archive: EvictionArchive?
    private let archiveRecents: Bool
    private let archiveFavorites: Bool

    public init(repository: any HistoryRepository, recentCapacity: Int = 40, favoriteCapacity: Int = 40, archive: EvictionArchive? = nil, archiveRecents: Bool = false, archiveFavorites: Bool = false) {
        self.archive = archive; self.archiveRecents = archiveRecents; self.archiveFavorites = archiveFavorites
        self.repository = repository
        self.recentCapacity = max(0, recentCapacity)
        self.favoriteCapacity = max(0, favoriteCapacity)
    }

    @discardableResult
    public func capture(_ clip: Clip) async throws -> HistorySnapshot {
        let capacity = recentCapacity
        let archive = archiveRecents ? archive : nil
        return try await repository.update { current in
            if clip.isUniversalControlSource && current.recent.contains(where: { $0.text == clip.text }) { return }
            if !clip.isUniversalControlSource {
                current.recent.removeAll { $0.isUniversalControlSource && $0.text == clip.text }
            }
            let key = DuplicateKey(clip)
            let retainedID = current.recent.first(where: { DuplicateKey($0) == key })?.id ?? clip.id
            current.recent.removeAll { DuplicateKey($0) == key }
            current.recent.insert(Clip(id: retainedID, text: clip.text, pasteboardType: clip.pasteboardType,
                                       sourceAppName: clip.sourceAppName, sourceBundleURL: clip.sourceBundleURL,
                                       capturedAt: clip.capturedAt, collection: .recent, order: 0,
                                       formattedRTF: clip.formattedRTF), at: 0)
            if current.recent.count > capacity {
                try archive?.save(Array(current.recent.suffix(current.recent.count - capacity)))
                current.recent.removeLast(current.recent.count - capacity)
            }
        }
    }

    @discardableResult
    public func normalizeRecents(backupTo backupURL: URL? = nil) async throws -> HistorySnapshot {
        try await repository.update { current in
            let otherSourceTexts = Set(current.recent.filter { !$0.isUniversalControlSource }.map(\.text))
            var seen = Set<DuplicateKey>()
            let retained = current.recent.filter {
                guard !$0.isUniversalControlSource || !otherSourceTexts.contains($0.text) else { return false }
                return seen.insert(DuplicateKey($0)).inserted
            }
            guard retained.count != current.recent.count else { return }
            if let backupURL { try Self.writePrivateBackup(current, to: backupURL) }
            current.recent = retained
        }
    }

    private static func writePrivateBackup(_ snapshot: HistorySnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HistoryError.database("Unable to create private history backup") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public func search(_ query: String) async throws -> [Clip] {
        let before = try await repository.snapshot()
        guard !query.isEmpty else { return before.recent + before.favorites }
        return (before.recent + before.favorites).filter { $0.text.localizedStandardContains(query) }
    }

    @discardableResult
    public func favorite(id: UUID) async throws -> HistorySnapshot {
        let capacity = favoriteCapacity
        let archive = archiveFavorites ? archive : nil
        return try await repository.update { current in
            guard let selected = current.recent.first(where: { $0.id == id }) else { throw HistoryError.missingClip }
            current.favorites.insert(Clip(id: selected.id, text: selected.text, pasteboardType: selected.pasteboardType, sourceAppName: selected.sourceAppName, sourceBundleURL: selected.sourceBundleURL, capturedAt: selected.capturedAt, collection: .favorite, order: 0, formattedRTF: selected.formattedRTF), at: 0)
            if current.favorites.count > capacity {
                try archive?.save(Array(current.favorites.suffix(current.favorites.count - capacity)))
                current.favorites.removeLast(current.favorites.count - capacity)
            }
            current.recent.removeAll { $0.id == id }
        }
    }

    @discardableResult
    public func clearRecents() async throws -> HistorySnapshot {
        try await repository.apply(.clear(.recent))
    }

    @discardableResult
    public func delete(id: UUID) async throws -> HistorySnapshot {
        try await repository.apply(.delete(id))
    }

    @discardableResult
    public func moveToTop(id: UUID) async throws -> HistorySnapshot {
        try await repository.apply(.moveToTop(id))
    }

    @discardableResult
    public func mergeAll() async throws -> Clip? {
        let snapshot = try await repository.update { current in
            guard let newest = current.recent.first else { return }
            let merged = Clip(id: UUID(), text: current.recent.reversed().map(\.text).joined(separator: "\n"), pasteboardType: newest.pasteboardType, sourceAppName: nil, sourceBundleURL: nil, capturedAt: Date(), collection: .recent, order: 0)
            current.recent = [merged]
        }
        return snapshot.recent.first
    }
}

private extension Clip {
    var isUniversalControlSource: Bool {
        sourceAppName == "Universal Control" || sourceBundleURL?.contains("/UniversalControl.app/") == true
    }
}
