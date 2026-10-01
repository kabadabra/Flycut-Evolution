import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor final class ImagePreviewModel: ObservableObject {
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var preview: NSImage?
    @Published private(set) var error: String?
    private let read: @Sendable (String) async throws -> Data?
    private var order: [String] = []
    private var loading = Set<String>()
    private var generation = UUID()
    init(read: @escaping @Sendable (String) async throws -> Data? = { _ in nil }) { self.read = read }
    func loadThumbnail(hash: String) async {
        guard thumbnails[hash] == nil, loading.insert(hash).inserted else { return }
        defer { loading.remove(hash) }
        guard let data = try? await read(hash) else { return }
        let small = await Task.detached(priority: .utility) { Self.thumbnail(data) }.value
        guard let small, let image = NSImage(data: small) else { return }
        thumbnails[hash] = image; order.append(hash)
        // 256×256 RGBA thumbnails use at most 256 KiB each; 128 fit in 32 MiB.
        while order.count > 128 { thumbnails[order.removeFirst()] = nil }
    }
    func load(hash: String) async {
        generation = UUID(); let request = generation; preview = nil; error = nil
        let data = try? await read(hash)
        guard request == generation, !Task.isCancelled else { return }
        guard let data, let image = NSImage(data: data) else { error = "Image could not be loaded."; return }
        preview = image
    }
    func cancel() { generation = UUID(); preview = nil; error = nil }
    nonisolated private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
