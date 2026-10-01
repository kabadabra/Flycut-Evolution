import Foundation

public struct CloudClipEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let clip: Clip?
    public let changedAt: Date
    public let origin: String
    public let imageRecord: Bool?
    public var isImage: Bool { imageRecord == true || clip?.image != nil }

    public init(id: UUID, clip: Clip?, changedAt: Date, origin: String, imageRecord: Bool? = nil) {
        self.id = id
        self.clip = clip
        self.changedAt = changedAt
        self.origin = origin
        self.imageRecord = clip?.image != nil ? true : imageRecord
    }
}

/// Pure merge model; CloudKit transport and local persistence are separate.
public struct CloudSyncLedger: Codable, Equatable, Sendable {
    public let deviceID: String
    public private(set) var entries: [UUID: CloudClipEntry] = [:]
    public private(set) var pendingIDs: Set<UUID> = []
    private var lastClock: Date = .distantPast

    public init(deviceID: String) { self.deviceID = deviceID }

    public var pendingEntries: [CloudClipEntry] {
        pendingIDs.sorted { $0.uuidString < $1.uuidString }.compactMap { entries[$0] }
    }

    @discardableResult
    public mutating func absorbUntrackedLocal(_ snapshot: HistorySnapshot, at date: Date) -> [UUID] {
        var added: [UUID] = []
        for clip in (snapshot.recent + snapshot.favorites).sorted(by: { $0.id.uuidString < $1.id.uuidString }) where entries[clip.id] == nil {
            entries[clip.id] = CloudClipEntry(id: clip.id, clip: Self.materializeFavorite(clip), changedAt: tick(date), origin: deviceID)
            pendingIDs.insert(clip.id)
            added.append(clip.id)
        }
        return added
    }

    @discardableResult
    public mutating func recordLocal(_ snapshot: HistorySnapshot, at date: Date, includeImages: Bool = true) -> [UUID] {
        let current = Dictionary(uniqueKeysWithValues: (snapshot.recent + snapshot.favorites).map { let clip = Self.materializeFavorite($0); return (clip.id, clip) })
        var changed: [UUID] = []
        for clip in current.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where includeImages || clip.image == nil {
            if let existing = entries[clip.id]?.clip, Self.sameContent(existing, clip) { continue }
            let entry = CloudClipEntry(id: clip.id, clip: clip, changedAt: tick(date), origin: deviceID)
            entries[clip.id] = entry
            pendingIDs.insert(clip.id)
            changed.append(clip.id)
        }
        for id in entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) where current[id] == nil && entries[id]?.clip != nil && (includeImages || entries[id]?.isImage != true) {
            entries[id] = CloudClipEntry(id: id, clip: nil, changedAt: tick(date), origin: deviceID, imageRecord: entries[id]?.isImage == true ? true : nil)
            pendingIDs.insert(id)
            changed.append(id)
        }
        return changed
    }

    public mutating func applyRemote(_ remote: [CloudClipEntry], to snapshot: HistorySnapshot, at date: Date, includeImages: Bool = true) -> HistorySnapshot {
        for incoming in remote where includeImages || (!incoming.isImage && entries[incoming.id]?.isImage != true) {
            lastClock = max(lastClock, incoming.changedAt)
            guard let current = entries[incoming.id] else {
                entries[incoming.id] = incoming
                continue
            }
            if Self.precedes(current, incoming) {
                entries[incoming.id] = incoming
                pendingIDs.remove(incoming.id)
            }
        }

        let synced = entries.values.compactMap(\.clip).filter { includeImages || $0.image == nil }
        let live = synced + (includeImages ? [] : (snapshot.recent + snapshot.favorites).filter { $0.image != nil })
        let sortedRecents = live.filter { $0.collection == .recent }.sorted(by: Self.newer)
        var seen = Set<DuplicateKey>()
        var keptRecents: [Clip] = []
        for clip in sortedRecents {
            if seen.insert(DuplicateKey(clip)).inserted { keptRecents.append(clip) }
            else {
                entries[clip.id] = CloudClipEntry(id: clip.id, clip: nil, changedAt: tick(date), origin: deviceID, imageRecord: clip.image != nil ? true : nil)
                pendingIDs.insert(clip.id)
            }
        }
        let favorites = live.filter { $0.collection == .favorite }.map(Self.materializeFavorite).sorted {
            let lhs = $0.favoriteMetadata?.rank ?? $0.order, rhs = $1.favoriteMetadata?.rank ?? $1.order
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
        return HistorySnapshot(recent: keptRecents.enumerated().map { Self.withOrder($0.element, $0.offset) },
                               favorites: favorites.enumerated().map { Self.withOrder($0.element, $0.offset) },
                               migration: snapshot.migration)
    }

    public mutating func acknowledge(_ ids: [UUID]) {
        for id in ids { pendingIDs.remove(id) }
    }

    public mutating func clearPending() { pendingIDs.removeAll() }

    private mutating func tick(_ date: Date) -> Date {
        let next = max(date, lastClock.addingTimeInterval(0.000_001))
        lastClock = next
        return next
    }

    private static func sameContent(_ lhs: Clip, _ rhs: Clip) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.pasteboardType == rhs.pasteboardType &&
        lhs.sourceAppName == rhs.sourceAppName && lhs.sourceBundleURL == rhs.sourceBundleURL &&
        lhs.capturedAt == rhs.capturedAt && lhs.collection == rhs.collection &&
        lhs.formattedRTF == rhs.formattedRTF && lhs.favoriteMetadata == rhs.favoriteMetadata && lhs.image == rhs.image && lhs.files == rhs.files && lhs.sourceBundleIdentifier == rhs.sourceBundleIdentifier
    }

    private static func precedes(_ lhs: CloudClipEntry, _ rhs: CloudClipEntry) -> Bool {
        if lhs.changedAt != rhs.changedAt { return lhs.changedAt < rhs.changedAt }
        if (lhs.clip == nil) != (rhs.clip == nil) { return rhs.clip == nil }
        return lhs.origin < rhs.origin
    }

    private static func newer(_ lhs: Clip, _ rhs: Clip) -> Bool {
        if lhs.capturedAt != rhs.capturedAt { return (lhs.capturedAt ?? .distantPast) > (rhs.capturedAt ?? .distantPast) }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func materializeFavorite(_ clip: Clip) -> Clip {
        guard clip.collection == .favorite, clip.favoriteMetadata == nil else { return clip }
        return clip.withFavoriteMetadata(.init(rank: clip.order))
    }
    private static func withOrder(_ clip: Clip, _ order: Int) -> Clip { clip.withOrder(order) }
    private struct DuplicateKey: Hashable {
        let text: String
        let source: String
        init(_ clip: Clip) {
            text = clip.contentIdentity
            if let name = clip.sourceAppName { source = "name:\(name)" }
            else if let url = clip.sourceBundleURL { source = "url:\(url)" }
            else { source = "unknown" }
        }
    }
}
