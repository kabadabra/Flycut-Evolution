import AppKit

@MainActor enum MenuBarIcon {
    static func configure(_ button: NSButton, choice: Int) {
        let symbol: String
        let configuration: NSImage.SymbolConfiguration
        switch choice {
        case 1:
            symbol = "scissors"
            configuration = .init(pointSize: 11, weight: .bold)
        case 2:
            symbol = "text.alignleft"
            configuration = .init(pointSize: 12, weight: .semibold)
        default:
            symbol = "doc.on.clipboard"
            configuration = .init(pointSize: 13, weight: .semibold)
        }
        button.symbolConfiguration = configuration
        button.imageScaling = .scaleNone
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flycut clipboard history")
        button.image = image?.withSymbolConfiguration(configuration) ?? image
    }
}
