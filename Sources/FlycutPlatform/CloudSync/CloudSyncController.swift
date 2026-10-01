import CloudKit
import Foundation
import FlycutCore

public enum CloudSyncError: Error, Equatable, Sendable {
    case accountChanged
    case notPrepared
    case unavailable
}

public enum CloudSyncStatus: Equatable, Sendable {
    case off
    case connecting
    case syncing
    case upToDate(Date?)
    case accountChanged
    case unavailable
    case error(String)
}

/// Owns CloudKit transport. The caller serializes history writes; startup
/// reconciles any local changes that were saved before the sync journal.
public actor CloudSyncController: CKSyncEngineDelegate {
    public typealias AccountIdentity = @Sendable () async throws -> String
    public typealias RemoteHandler = @Sendable ([CloudClipEntry]) async -> Void
    public typealias StatusHandler = @Sendable (CloudSyncStatus) async -> Void

    private let store: CloudSyncStateStore
    private let container: CKContainer?
    private let accountIdentity: AccountIdentity
    private let onRemote: RemoteHandler
    private let onRemoteImages: @Sendable ([CloudImageEnvelope]) async -> Void
    private let imageReader: @Sendable (String) async throws -> Data?
    private var imageSyncEnabled: Bool
    private let onStatus: StatusHandler
    private let onAccountInvalidated: @Sendable () async -> Void
    private let requiresEntitlement: Bool
    private let zoneID = CKRecordZone.ID(zoneName: CloudRecordCodec.zoneName)
    private var state: CloudSyncDiskState?
    private var engine: CKSyncEngine?
    private var active = false
    private var fetchApplicationFailed = false

    public init(store: CloudSyncStateStore,
                container: CKContainer? = nil,
                accountIdentity: AccountIdentity? = nil,
                onRemote: @escaping RemoteHandler,
                onStatus: @escaping StatusHandler,
                onAccountInvalidated: @escaping @Sendable () async -> Void = {},
                imageSyncEnabled: Bool = false,
                imageReader: @escaping @Sendable (String) async throws -> Data? = { _ in nil },
                onRemoteImages: @escaping @Sendable ([CloudImageEnvelope]) async -> Void = { _ in }) {
        self.store = store
        self.container = container
        self.requiresEntitlement = accountIdentity == nil
        self.accountIdentity = accountIdentity ?? {
            try await CKContainer(identifier: "iCloud.com.edynamics.flycut").userRecordID().recordName
        }
        self.imageSyncEnabled = imageSyncEnabled; self.imageReader = imageReader; self.onRemoteImages = onRemoteImages
        self.onRemote = onRemote
        self.onStatus = onStatus
        self.onAccountInvalidated = onAccountInvalidated
    }

    /// Called only after the user opts in, or on a later launch with saved opt-in.
    /// A changed account requires another explicit opt-in.
    public func prepare(_ snapshot: HistorySnapshot, reauthorize: Bool) async throws -> HistorySnapshot {
        await onStatus(.connecting)
        if requiresEntitlement && !CloudSyncEntitlement.available() {
            await onStatus(.unavailable)
            throw CloudSyncError.unavailable
        }
        let account: String
        do { account = try await accountIdentity() }
        catch { await onStatus(.unavailable); throw CloudSyncError.unavailable }
        let prior = try store.load()
        guard prior == nil || prior?.accountID == account || reauthorize else {
            await onStatus(.accountChanged)
            throw CloudSyncError.accountChanged
        }
        var next: CloudSyncDiskState
        if let prior, prior.accountID == account { next = prior }
        else { next = CloudSyncDiskState(accountID: account, ledger: CloudSyncLedger(deviceID: UUID().uuidString)) }
        _ = next.ledger.recordLocal(snapshot, at: Date(), includeImages: imageSyncEnabled)
        let recovered = next.ledger.applyRemote([], to: snapshot, at: Date(), includeImages: imageSyncEnabled)
        try store.save(next)
        state = next
        fetchApplicationFailed = next.unappliedDownloads == true
        active = true
        return recovered
    }

    public func activate() async throws {
        guard active, let state else { throw CloudSyncError.notPrepared }
        let cloudContainer = container ?? CKContainer(identifier: "iCloud.com.edynamics.flycut")
        var configuration = CKSyncEngine.Configuration(database: cloudContainer.privateCloudDatabase,
                                                        stateSerialization: state.engineState, delegate: self)
        configuration.automaticallySync = true
        let newEngine = CKSyncEngine(configuration)
        engine = newEngine
        newEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        queuePendingChanges()
        await onStatus(.syncing)
    }

    public func stop() async {
        active = false
        engine = nil
        await onStatus(.off)
    }

    public func recordLocal(_ snapshot: HistorySnapshot) async throws {
        guard active, var next = state else { return }
        let changed = next.ledger.recordLocal(snapshot, at: Date(), includeImages: imageSyncEnabled)
        guard !changed.isEmpty else { return }
        try store.save(next)
        state = next
        queuePendingChanges(ids: changed)
        await onStatus(.syncing)
    }

    public func mergeRemote(_ remote: [CloudClipEntry], into snapshot: HistorySnapshot,
                            apply: @Sendable (HistorySnapshot) async throws -> Void) async throws -> HistorySnapshot {
        try await mergeRemoteApplied(remote, into: snapshot) { merged in
            try await apply(merged)
            return merged
        }
    }
    /// Persist the bounded collection and its eviction tombstones together in the
    /// sync journal; omitted overflow must not be reintroduced by another fetch.
    public func mergeRemoteApplied(_ remote: [CloudClipEntry], into snapshot: HistorySnapshot,
                                   apply: @Sendable (HistorySnapshot) async throws -> HistorySnapshot) async throws -> HistorySnapshot {
        guard active, var next = state else { return snapshot }
        let merged = next.ledger.applyRemote(remote, to: snapshot, at: Date(), includeImages: imageSyncEnabled)
        do {
            let retained = try await apply(merged)
            _ = next.ledger.recordLocal(retained, at: Date(), includeImages: imageSyncEnabled)
            try store.save(next)
            state = next
            queuePendingChanges()
            return retained
        } catch {
            fetchApplicationFailed = true
            if var failureState = state {
                failureState.unappliedDownloads = true
                try? store.save(failureState)
                state = failureState
            }
            await onStatus(.error("Cloud Sync could not apply downloaded history. Check the history or image storage limit. Local history is available."))
            throw error
        }
    }
    func completeFetchAttempt() async {
        guard var next = state else { return }
        guard !fetchApplicationFailed else {
            next.unappliedDownloads = true
            do { try store.save(next); state = next } catch {}
            await onStatus(.error("Some downloaded history was not applied. Increase the image limit if needed, then choose Sync Now to retry."))
            return
        }
        next.lastSuccess = Date()
        do { try store.save(next); state = next; await onStatus(.upToDate(next.lastSuccess)) }
        catch { await onStatus(.error("Cloud Sync state could not be saved.")) }
    }

    func completeUploadAttempt() async {
        await completeFetchAttempt()
    }

    public func setImageSyncEnabled(_ enabled: Bool) async throws {
        guard enabled != imageSyncEnabled else { return }
        imageSyncEnabled = enabled
        if let engine, let state {
            let pendingImages = engine.state.pendingRecordZoneChanges.filter { change in
                switch change {
                case .saveRecord(let id), .deleteRecord(let id): return UUID(uuidString: id.recordName).map { state.ledger.entries[$0]?.isImage == true } ?? false
                @unknown default: return false
                }
            }
            engine.state.remove(pendingRecordZoneChanges: pendingImages)
            if enabled {
                // Previously skipped image records need a fresh fetch cursor.
                var next = state; next.engineState = nil; next.unappliedDownloads = nil
                try store.save(next); self.state = next; fetchApplicationFailed = false
                self.engine = nil; try await activate()
            }
        }
    }
    public func syncNow() async throws {
        guard active else { throw CloudSyncError.notPrepared }
        if fetchApplicationFailed, var next = state {
            next.engineState = nil; next.unappliedDownloads = nil
            try store.save(next); state = next; fetchApplicationFailed = false
            self.engine = nil; try await activate()
        }
        guard let engine else { throw CloudSyncError.notPrepared }
        try await engine.fetchChanges()
        try await engine.sendChanges()
    }

    public var lastSuccessfulSync: Date? { state?.lastSuccess }

    private func queuePendingChanges(ids: [UUID]? = nil) {
        guard let engine, let state else { return }
        let changes = (ids ?? Array(state.ledger.pendingIDs)).filter { imageSyncEnabled || state.ledger.entries[$0]?.isImage != true }.map { id in
            CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
        }
        if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
    }

    /// A downloaded record's change tag is required when this Mac edits it.
    func saveFetchedSystemFields(_ records: [CKRecord]) throws {
        guard active, var next = state else { throw CloudSyncError.notPrepared }
        for record in records where record.recordID.zoneID == zoneID {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            next.systemFields[id] = Self.encodeSystemFields(record)
        }
        try store.save(next)
        state = next
    }

    private func checkAccount() async -> Bool {
        guard active, let state else { return false }
        guard let account = try? await accountIdentity() else {
            await onStatus(.unavailable)
            return false
        }
        guard account == state.accountID else {
            active = false
            engine = nil
            await onStatus(.accountChanged)
            await onAccountInvalidated()
            return false
        }
        return true
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard await checkAccount(), let state else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { change in
            guard context.options.scope.contains(change) else { return false }
            switch change {
            case .saveRecord(let id), .deleteRecord(let id): return imageSyncEnabled || UUID(uuidString: id.recordName).map { state.ledger.entries[$0]?.isImage != true } == true
            @unknown default: return false
            }
        }
        guard !changes.isEmpty else { return nil }
        let entries = state.ledger.entries
        let fields = state.systemFields
        let imageReader = self.imageReader
        let assetDirectory = store.url.deletingLastPathComponent().appendingPathComponent("Cloud Assets", isDirectory: true)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            guard let uuid = UUID(uuidString: id.recordName), let entry = entries[uuid] else { return nil }
            do {
                let base = Self.decodeSystemFields(fields[uuid])
                if entry.isImage {
                    let asset: ImageAsset?
                    if let hash = entry.clip?.image?.assetHash {
                        guard let png = try await imageReader(hash) else { return nil }
                        asset = .init(hash: hash, png: png)
                    } else { asset = nil }
                    return try CloudImageCodec.record(for: .init(entry: entry, asset: asset), zoneID: id.zoneID, assetDirectory: assetDirectory, baseRecord: base)
                }
                return try CloudRecordCodec.record(for: entry, zoneID: id.zoneID,
                                                   assetDirectory: assetDirectory, baseRecord: base)
            } catch { return nil }
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard active else { return }
        switch event {
        case .stateUpdate(let update):
            guard var next = state else { return }
            next.engineState = update.stateSerialization
            do { try store.save(next); state = next }
            catch { await onStatus(.error("Cloud Sync state could not be saved.")) }

        case .accountChange:
            _ = await checkAccount()

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                active = false
                engine = nil
                await onStatus(.error("Cloud history was removed. Local history is safe; enable sync again to reconnect."))
                await onAccountInvalidated()
            }

        case .fetchedRecordZoneChanges(let changes):
            var remote: [CloudClipEntry] = []
            var images: [CloudImageEnvelope] = []
            for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
                if modification.record.recordType == CloudImageCodec.recordType {
                    if imageSyncEnabled {
                        do { images.append(try CloudImageCodec.envelope(from: modification.record)) }
                        catch { fetchApplicationFailed = true; await onStatus(.error("A cloud image could not be read.")) }
                    }
                    continue
                }
                do { remote.append(try CloudRecordCodec.entry(from: modification.record)) }
                catch { fetchApplicationFailed = true; await onStatus(.error("A cloud clipping could not be read.")) }
            }
            for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                if deletion.recordType == CloudImageCodec.recordType && !imageSyncEnabled { continue }
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    remote.append(CloudClipEntry(id: id, clip: nil, changedAt: Date(), origin: "cloud-deletion", imageRecord: deletion.recordType == CloudImageCodec.recordType ? true : nil))
                }
            }
            if !images.isEmpty { await onRemoteImages(images) }
            if !remote.isEmpty { await onRemote(remote) }
            do { try saveFetchedSystemFields(changes.modifications.map(\.record)) }
            catch { fetchApplicationFailed = true; await onStatus(.error("Cloud Sync could not save downloaded record state.")) }

        case .sentRecordZoneChanges(let sent):
            guard var next = state else { return }
            var acknowledged: [UUID] = []
            for saved in sent.savedRecords {
                guard let id = UUID(uuidString: saved.recordID.recordName) else { continue }
                next.systemFields[id] = Self.encodeSystemFields(saved)
                if let sentEntry = Self.entryFromAnyRecord(saved), next.ledger.entries[id] == sentEntry {
                    acknowledged.append(id)
                }
                if let asset = saved["payloadAsset"] as? CKAsset { removeOwnedAsset(asset.fileURL) }
            }
            next.ledger.acknowledge(acknowledged)
            do {
                try store.save(next); state = next
                if sent.failedRecordSaves.isEmpty || fetchApplicationFailed { await completeUploadAttempt() }
            } catch { await onStatus(.error("Cloud Sync state could not be saved.")) }
            for failure in sent.failedRecordSaves {
                if let asset = failure.record["payloadAsset"] as? CKAsset { removeOwnedAsset(asset.fileURL) }
                if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                    if server.recordType == CloudImageCodec.recordType {
                        if imageSyncEnabled, let image = try? CloudImageCodec.envelope(from: server) { await onRemoteImages([image]) }
                    } else if let entry = try? CloudRecordCodec.entry(from: server) { await onRemote([entry]) }
                    do { try saveFetchedSystemFields([server]) }
                    catch { fetchApplicationFailed = true; await onStatus(.error("Cloud Sync could not save downloaded record state.")) }
                }
                if failure.error.code == .zoneNotFound {
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                }
                if failure.error.code == .serverRecordChanged || failure.error.code == .zoneNotFound || failure.error.code == .unknownItem {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                } else if ![CKError.networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled].contains(failure.error.code) {
                    await onStatus(.error("A cloud clipping could not be saved."))
                }
            }
            queuePendingChanges()

        case .sentDatabaseChanges(let sent):
            if !sent.failedZoneSaves.isEmpty { await onStatus(.error("Cloud history could not be created.")) }

        case .didFetchChanges:
            await completeFetchAttempt()

        case .didFetchRecordZoneChanges(let finished):
            if finished.error != nil { fetchApplicationFailed = true; await onStatus(.error("Cloud Sync could not fetch changes. It will retry.")) }

        case .willFetchChanges:
            await onStatus(.syncing)
        case .willFetchRecordZoneChanges, .willSendChanges:
            await onStatus(.syncing)
        case .didSendChanges:
            if fetchApplicationFailed || state?.ledger.pendingIDs.isEmpty == true { await completeUploadAttempt() }
        @unknown default: break
        }
    }

    private static func entryFromAnyRecord(_ record: CKRecord) -> CloudClipEntry? {
        if record.recordType == CloudImageCodec.recordType { return (try? CloudImageCodec.envelope(from: record))?.entry }
        return try? CloudRecordCodec.entry(from: record)
    }
    private func removeOwnedAsset(_ url: URL?) {
        guard let url, url.pathExtension == "upload",
              url.deletingLastPathComponent().standardizedFileURL == store.url.deletingLastPathComponent()
                .appendingPathComponent("Cloud Assets").standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data?) -> CKRecord? {
        guard let data, let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }
}
