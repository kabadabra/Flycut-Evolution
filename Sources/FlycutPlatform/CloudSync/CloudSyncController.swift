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
    private let onStatus: StatusHandler
    private let onAccountInvalidated: @Sendable () async -> Void
    private let requiresEntitlement: Bool
    private let zoneID = CKRecordZone.ID(zoneName: CloudRecordCodec.zoneName)
    private var state: CloudSyncDiskState?
    private var engine: CKSyncEngine?
    private var active = false

    public init(store: CloudSyncStateStore,
                container: CKContainer? = nil,
                accountIdentity: AccountIdentity? = nil,
                onRemote: @escaping RemoteHandler,
                onStatus: @escaping StatusHandler,
                onAccountInvalidated: @escaping @Sendable () async -> Void = {}) {
        self.store = store
        self.container = container
        self.requiresEntitlement = accountIdentity == nil
        self.accountIdentity = accountIdentity ?? {
            try await CKContainer(identifier: "iCloud.com.edynamics.flycut").userRecordID().recordName
        }
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
        _ = next.ledger.recordLocal(snapshot, at: Date())
        let recovered = next.ledger.applyRemote([], to: snapshot, at: Date())
        try store.save(next)
        state = next
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
        let changed = next.ledger.recordLocal(snapshot, at: Date())
        guard !changed.isEmpty else { return }
        try store.save(next)
        state = next
        queuePendingChanges(ids: changed)
        await onStatus(.syncing)
    }

    public func mergeRemote(_ remote: [CloudClipEntry], into snapshot: HistorySnapshot,
                            apply: @Sendable (HistorySnapshot) async throws -> Void) async throws -> HistorySnapshot {
        guard active, var next = state else { return snapshot }
        let merged = next.ledger.applyRemote(remote, to: snapshot, at: Date())
        // Keep SQLite ahead of the journal. If the process exits between these
        // writes, prepare() will detect and re-queue the local difference.
        try await apply(merged)
        try store.save(next)
        state = next
        queuePendingChanges()
        return merged
    }

    public func syncNow() async throws {
        guard active, let engine else { throw CloudSyncError.notPrepared }
        try await engine.fetchChanges()
        try await engine.sendChanges()
    }

    public var lastSuccessfulSync: Date? { state?.lastSuccess }

    private func queuePendingChanges(ids: [UUID]? = nil) {
        guard let engine, let state else { return }
        let changes = (ids ?? Array(state.ledger.pendingIDs)).map { id in
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
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        let entries = state.ledger.entries
        let fields = state.systemFields
        let assetDirectory = store.url.deletingLastPathComponent().appendingPathComponent("Cloud Assets", isDirectory: true)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            guard let uuid = UUID(uuidString: id.recordName), let entry = entries[uuid] else { return nil }
            do {
                let base = Self.decodeSystemFields(fields[uuid])
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
            for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
                do { remote.append(try CloudRecordCodec.entry(from: modification.record)) }
                catch { await onStatus(.error("A cloud clipping could not be read.")) }
            }
            for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    remote.append(CloudClipEntry(id: id, clip: nil, changedAt: Date(), origin: "cloud-deletion"))
                }
            }
            if !remote.isEmpty { await onRemote(remote) }
            do { try saveFetchedSystemFields(changes.modifications.map(\.record)) }
            catch { await onStatus(.error("Cloud Sync could not save downloaded record state.")) }

        case .sentRecordZoneChanges(let sent):
            guard var next = state else { return }
            var acknowledged: [UUID] = []
            for saved in sent.savedRecords {
                guard let id = UUID(uuidString: saved.recordID.recordName) else { continue }
                next.systemFields[id] = Self.encodeSystemFields(saved)
                if let sentEntry = try? CloudRecordCodec.entry(from: saved), next.ledger.entries[id] == sentEntry {
                    acknowledged.append(id)
                }
                if let asset = saved["payloadAsset"] as? CKAsset { removeOwnedAsset(asset.fileURL) }
            }
            next.ledger.acknowledge(acknowledged)
            next.lastSuccess = Date()
            do { try store.save(next); state = next; await onStatus(.upToDate(next.lastSuccess)) }
            catch { await onStatus(.error("Cloud Sync state could not be saved.")) }
            for failure in sent.failedRecordSaves {
                if let asset = failure.record["payloadAsset"] as? CKAsset { removeOwnedAsset(asset.fileURL) }
                if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                    if let entry = try? CloudRecordCodec.entry(from: server) { await onRemote([entry]) }
                    do { try saveFetchedSystemFields([server]) }
                    catch { await onStatus(.error("Cloud Sync could not save downloaded record state.")) }
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
            guard var next = state else { return }
            next.lastSuccess = Date()
            do { try store.save(next); state = next; await onStatus(.upToDate(next.lastSuccess)) }
            catch { await onStatus(.error("Cloud Sync state could not be saved.")) }

        case .didFetchRecordZoneChanges(let finished):
            if finished.error != nil { await onStatus(.error("Cloud Sync could not fetch changes. It will retry.")) }

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges, .didSendChanges:
            await onStatus(.syncing)
        @unknown default: break
        }
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
