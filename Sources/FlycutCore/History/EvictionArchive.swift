import Foundation
import Darwin

public struct EvictionArchive: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    /// Private files are written before capacity eviction; failure aborts eviction.
    public func save(_ clips: [Clip], imageAssets: [String: Data] = [:]) throws {
        guard !clips.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for clip in clips {
            let bytes: Data
            if let image = clip.image {
                guard let png = imageAssets[image.assetHash] else { throw HistoryError.database("Image export data is unavailable") }
                bytes = png
            } else { bytes = Data((clip.files?.map(\.path).joined(separator: "\n") ?? clip.text).utf8) }
            let url = directory.appendingPathComponent("Flycut-\(UUID().uuidString).\(clip.image == nil ? "txt" : "png")")
            let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw HistoryError.database("Unable to create private clipping export") }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do { try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); try? FileManager.default.removeItem(at: url); throw error }
        }
    }
}
