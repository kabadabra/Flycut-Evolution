/// A destination remains read-only until its complete snapshot has been restored.
/// Keeping this gate independent of the database handle prevents failed reads from
/// turning into destructive replacements during shutdown or subsequent captures.
public actor HistoryPersistence {
    private let destination: any HistoryRepository
    private var restored = false
    private var expectedDestination: HistorySnapshot?
    public init(destination: any HistoryRepository) { self.destination = destination }

    public func restore(into working: any HistoryRepository) async throws {
        restored = false
        expectedDestination = nil
        let snapshot = try await destination.snapshot()
        try await working.replaceAll(snapshot)
        expectedDestination = snapshot
        restored = true
    }

    @discardableResult
    public func save(_ snapshot: HistorySnapshot) async throws -> Bool {
        guard restored, let expectedDestination else { return false }
        let saved = try await destination.update { current in
            guard current == expectedDestination else { throw HistoryError.staleSnapshot }
            current = snapshot
        }
        self.expectedDestination = saved
        return true
    }
}
