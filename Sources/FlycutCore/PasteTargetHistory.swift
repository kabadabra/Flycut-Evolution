/// Tracks the preceding external application even while a sticky palette remains
/// visible. A paste action copies previousExternalApp before starting asynchronous
/// focus restoration, so later activations cannot redirect that action.
public struct PasteTargetHistory: Sendable {
    private let ownProcessID: Int32
    public private(set) var previousExternalApp: Int32?

    public init(ownProcessID: Int32) { self.ownProcessID = ownProcessID }

    public mutating func observeActivation(processID: Int32?) {
        guard let processID, processID != ownProcessID else { return }
        previousExternalApp = processID
    }
}
