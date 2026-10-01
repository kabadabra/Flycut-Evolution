import AppKit

public enum PasteboardReadResult: Equatable {
    case text(String)
    case unavailable
    case denied
}

public enum PasteboardImageReadResult: Equatable, Sendable {
    case data(Data, type: String), unavailable, denied
}
public enum PasteboardFileReadResult: Equatable, Sendable {
    case urls([URL]), unavailable, denied
}
enum PasteboardAccessEvidence: Equatable {
    case alwaysDeny
    case unknown
}

/// A small boundary around the system pasteboard; tests provide an in-memory implementation.
@MainActor public protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    var advertisedTypes: [String] { get }
    func readPlainText() -> PasteboardReadResult
    func readRTF() -> Data?
    func readImage() -> PasteboardImageReadResult
    func readFileURLs() -> PasteboardFileReadResult
}

public extension PasteboardClient {
    func readImage() -> PasteboardImageReadResult { .unavailable }
    func readFileURLs() -> PasteboardFileReadResult { .unavailable }
}

@MainActor public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }
    public var advertisedTypes: [String] { (pasteboard.types ?? []).map(\.rawValue) }

    public func readPlainText() -> PasteboardReadResult {
        let text = pasteboard.string(forType: .string)
        if let text { return Self.classifyRead(text, access: .unknown) }
        let access: PasteboardAccessEvidence
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            access = .alwaysDeny
        } else {
            access = .unknown
        }
        return Self.classifyRead(nil, access: access)
    }

    public func readImage() -> PasteboardImageReadResult {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return .denied }
        for type in ClipboardImageDecoder.types where advertisedTypes.contains(type) {
            if let data = pasteboard.data(forType: .init(type)) { return .data(data, type: type) }
        }
        return .unavailable
    }
    public func readFileURLs() -> PasteboardFileReadResult {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny { return .denied }
        if let values = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !values.isEmpty {
            guard values.count <= 100 else { return .unavailable }
            return .urls(values)
        }
        if let paths = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String], !paths.isEmpty, paths.count <= 100, paths.allSatisfy({ $0.hasPrefix("/") }) {
            return .urls(paths.map { URL(fileURLWithPath: $0) })
        }
        return .unavailable
    }
    public func readRTF() -> Data? { pasteboard.data(forType: .rtf) }

    nonisolated static func classifyRead(_ text: String?, access: PasteboardAccessEvidence) -> PasteboardReadResult {
        if let text { return .text(text) }
        return access == .alwaysDeny ? .denied : .unavailable
    }
}
