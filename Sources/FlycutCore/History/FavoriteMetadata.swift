import Foundation

public struct FavoriteMetadata: Codable, Equatable, Sendable {
    public var name: String?
    public var shortcut: Int?
    public var rank: Int
    public init(name: String? = nil, shortcut: Int? = nil, rank: Int) {
        self.name = name; self.shortcut = shortcut; self.rank = rank
    }
}

public struct FavoriteEdit: Equatable, Sendable {
    public var name: String
    public var text: String
    public var shortcut: Int?
    public init(name: String, text: String, shortcut: Int? = nil) {
        self.name = name; self.text = text; self.shortcut = shortcut
    }
}
