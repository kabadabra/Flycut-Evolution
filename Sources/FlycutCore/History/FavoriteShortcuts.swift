import Foundation

public enum FavoriteShortcutResolution: Equatable, Sendable {
    case missing, conflict, clip(UUID)
}
public enum FavoriteShortcuts {
    public static func resolve(slot: Int, favorites: [Clip]) -> FavoriteShortcutResolution {
        guard (1...9).contains(slot) else { return .missing }
        let matches = favorites.filter { $0.favoriteMetadata?.shortcut == slot }
        guard matches.count < 2 else { return .conflict }
        return matches.first.map { .clip($0.id) } ?? .missing
    }
}
