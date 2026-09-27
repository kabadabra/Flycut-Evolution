import AppKit

public enum PasteboardReadResult: Equatable {
    case text(String)
    case unavailable
    case denied
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

    public func readRTF() -> Data? { pasteboard.data(forType: .rtf) }

    nonisolated static func classifyRead(_ text: String?, access: PasteboardAccessEvidence) -> PasteboardReadResult {
        if let text { return .text(text) }
        return access == .alwaysDeny ? .denied : .unavailable
    }
}
