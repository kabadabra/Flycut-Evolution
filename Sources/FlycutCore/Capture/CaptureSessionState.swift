import Foundation

public enum CapturePause: Equatable, Sendable {
    case running, manual, until(Date)
}
public struct CaptureSessionState: Equatable, Sendable {
    public private(set) var pause: CapturePause = .running
    public private(set) var ignoresNextCopy = false
    public var isPaused: Bool { pause != .running }
    public init() {}
    public mutating func setPause(_ pause: CapturePause) { self.pause = pause }
    public mutating func resume() { pause = .running }
    public mutating func ignoreNextCopy() { ignoresNextCopy = true }
    public mutating func cancelIgnore() { ignoresNextCopy = false }
    public mutating func consumeExternalChange() -> Bool {
        let skip = ignoresNextCopy; ignoresNextCopy = false; return skip
    }
    public mutating func expire(at date: Date) -> Bool {
        guard case .until(let deadline) = pause, date >= deadline else { return false }
        resume(); return true
    }
}
