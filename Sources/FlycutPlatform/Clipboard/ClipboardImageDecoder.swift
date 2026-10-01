import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import FlycutCore

public enum ClipboardImageDecoder {
    public static let types = ["public.png", "public.tiff", "public.jpeg"]
    public static func decodeFile(_ url: URL) throws -> ImageAssetCapture {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 16 * 1024 * 1024,
              values.contentType?.conforms(to: .image) == true else { throw HistoryError.database("Image file is unavailable or exceeds the capture limits") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the read even if the file grows or is replaced after the size check.
        guard let data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) else { throw HistoryError.database("Image file could not be read") }
        return try decode(data, type: "public.png")
    }
    public static func decode(_ data: Data, type: String) throws -> ImageAssetCapture {
        guard types.contains(type), !data.isEmpty, data.count <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 24_000_000 / height else { throw HistoryError.database("Image is invalid or exceeds the capture limits") }
        // ImageIO applies orientation while making the full-resolution image.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary) else { throw HistoryError.database("Image could not be decoded") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw HistoryError.database("Image could not be normalized") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 16 * 1024 * 1024 else { throw HistoryError.database("Normalized image exceeds 16 MiB") }
        let png = output as Data
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return .init(asset: .init(hash: hash, png: png), width: image.width, height: image.height)
    }
}
