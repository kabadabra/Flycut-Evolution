import CloudKit
import Foundation
import Darwin
import FlycutCore

public struct CloudSyncDiskState: Codable, Sendable {
    public let accountID: String
    public var ledger: CloudSyncLedger
    public var engineState: CKSyncEngine.State.Serialization?
    public var systemFields: [UUID: Data]
    public var lastSuccess: Date?
    public var unappliedDownloads: Bool?

    public init(accountID: String, ledger: CloudSyncLedger,
                engineState: CKSyncEngine.State.Serialization? = nil,
                systemFields: [UUID: Data] = [:], lastSuccess: Date? = nil) {
        self.accountID = accountID
        self.ledger = ledger
        self.engineState = engineState
        self.systemFields = systemFields
        self.lastSuccess = lastSuccess
        self.unappliedDownloads = nil
    }
}

public struct CloudSyncStateStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> CloudSyncDiskState? {
        do { return try JSONDecoder().decode(CloudSyncDiskState.self, from: Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func save(_ state: CloudSyncDiskState) throws {
        let data = try JSONEncoder().encode(state)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CloudRecordError.unableToWriteAsset }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard Darwin.rename(temporary.path, url.path) == 0 else {
                throw CloudRecordError.unableToWriteAsset
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
