import Foundation
public enum SetupStep: Int, Codable, CaseIterable, Sendable { case privacy, shortcuts, permissions, paste, updates }
public struct SetupState: Codable, Equatable, Sendable {
    public var completed = false
    public var dismissed = false
    public var step: SetupStep = .privacy
    public var handled: Bool { completed || dismissed }
    public init() {}
}
