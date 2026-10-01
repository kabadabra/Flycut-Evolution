import FlycutCore

/// Called from the coordinator's serialized queue; publishing and sync happen
/// only after this returns a snapshot whose required local save succeeded.
@MainActor enum FavoriteMutation {
    static func perform(repository: any HistoryRepository,
                        operation: @MainActor () async throws -> Void,
                        persist: @MainActor (HistorySnapshot) async throws -> Void) async throws -> HistorySnapshot {
        let before = try await repository.snapshot()
        let images = repository as? any ImageAssetRepository
        let assets = try await images?.exportAssets(for: before) ?? []
        do {
            try await operation()
            let after = try await repository.snapshot()
            try await persist(after)
            return after
        } catch {
            if let images { try await images.replaceAll(before, assets: assets, expected: nil) }
            else { try await repository.replaceAll(before) }
            throw error
        }
    }
}
