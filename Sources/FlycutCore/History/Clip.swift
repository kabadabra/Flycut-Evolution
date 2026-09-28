import Foundation

public enum FlycutVersion {
    public static let current = "1.0.1"
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

    public init(
        id: UUID,
        text: String,
        pasteboardType: String,
        sourceAppName: String?,
        sourceBundleURL: String?,
        capturedAt: Date?,
        collection: CollectionKind,
        order: Int,
        formattedRTF: Data? = nil
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
    }

    /// A compact label only; the stored clipping retains its original whitespace.
    public func previewLine(limit: Int) -> String {
        let maximum = max(1, limit)
        var characters: [Character] = []
        var pendingSpace = false
        for character in text {
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
