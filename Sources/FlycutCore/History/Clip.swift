import Foundation

public enum FlycutVersion {
    public static let current = "1.0.2"
}

public enum CollectionKind: String, Codable, Sendable {
    case recent
    case favorite
}

public struct Clip: Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let pasteboardType: String
    public let sourceAppName: String?
    public let sourceBundleURL: String?
    public let capturedAt: Date?
    public let collection: CollectionKind
    public let order: Int
    /// Original RTF for text-only styled copies; nil for older or plain clips.
    public let formattedRTF: Data?
    public let favoriteMetadata: FavoriteMetadata?
    public let image: ClipImage?
    public let sourceBundleIdentifier: String?
    public let files: [ClipFile]?
    public var contentKind: ClipContentKind { image != nil ? .image : (files?.isEmpty == false ? .file : .text) }
    public var searchableText: String {
        ([text, image?.accompanyingText, image?.recognizedText].compactMap { $0 } + (files ?? []).map(\.path)).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public init(
        id: UUID,
        text: String,
        pasteboardType: String,
        sourceAppName: String?,
        sourceBundleURL: String?,
        capturedAt: Date?,
        collection: CollectionKind,
        order: Int,
        formattedRTF: Data? = nil,
        favoriteMetadata: FavoriteMetadata? = nil,
        image: ClipImage? = nil,
        sourceBundleIdentifier: String? = nil,
        files: [ClipFile]? = nil
    ) {
        self.id = id
        self.text = text
        self.pasteboardType = pasteboardType
        self.sourceAppName = sourceAppName
        self.sourceBundleURL = sourceBundleURL
        self.capturedAt = capturedAt
        self.collection = collection
        self.order = order
        self.formattedRTF = formattedRTF
        self.favoriteMetadata = favoriteMetadata
        self.image = image; self.sourceBundleIdentifier = sourceBundleIdentifier; self.files = files
    }

    public func withOrder(_ order: Int) -> Clip {
        Clip(id: id, text: text, pasteboardType: pasteboardType, sourceAppName: sourceAppName,
             sourceBundleURL: sourceBundleURL, capturedAt: capturedAt, collection: collection,
             order: order, formattedRTF: formattedRTF, favoriteMetadata: favoriteMetadata, image: image, sourceBundleIdentifier: sourceBundleIdentifier, files: files)
    }

    public func withFavoriteMetadata(_ metadata: FavoriteMetadata) -> Clip {
        Clip(id: id, text: text, pasteboardType: pasteboardType, sourceAppName: sourceAppName,
             sourceBundleURL: sourceBundleURL, capturedAt: capturedAt, collection: collection,
             order: order, formattedRTF: formattedRTF, favoriteMetadata: metadata, image: image, sourceBundleIdentifier: sourceBundleIdentifier, files: files)
    }

    /// A compact label only; the stored clipping retains its original whitespace.
    public func previewLine(limit: Int) -> String {
        let maximum = max(1, limit)
        var characters: [Character] = []
        var pendingSpace = false
        if let image, searchableText.isEmpty { return "Image · \(image.width) × \(image.height)" }
        let label = files.flatMap { $0.isEmpty ? nil : $0.map(\.name).joined(separator: ", ") } ?? searchableText
        for character in label {
            if character.isWhitespace {
                pendingSpace = !characters.isEmpty
                continue
            }
            if pendingSpace { characters.append(" ") }
            characters.append(character)
            pendingSpace = false
            if characters.count > maximum {
                let visible = characters.prefix(maximum).drop(while: { $0 == " " })
                let line = String(visible).trimmingCharacters(in: .whitespaces)
                return line + "…"
            }
        }
        return String(characters)
    }
}
