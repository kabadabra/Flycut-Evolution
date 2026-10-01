import Foundation

/// File references preserve their original location; document bytes are not stored.
public struct ClipFile: Codable, Equatable, Sendable {
    public let urlString: String
    public var url: URL { URL(string: urlString)! }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }
    public init(url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), !url.path.contains("\0"), url.absoluteString.count <= 16_384 else {
            throw HistoryError.database("Invalid local file reference")
        }
        urlString = url.absoluteString
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let value = try values.decode(String.self, forKey: .urlString)
        guard let url = URL(string: value) else { throw HistoryError.database("Invalid local file reference") }
        try self.init(url: url)
    }
}

extension Clip {
    /// Includes location so equal filenames and equal pixels from different files remain distinct.
    var contentIdentity: String {
        let value = image.map { "image:\($0.assetHash)" } ?? (files == nil ? "text:\(text)" : "file")
        return value + (files ?? []).map { "\0\($0.urlString)" }.joined()
    }
}
