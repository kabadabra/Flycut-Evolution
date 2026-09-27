import AppKit
import SwiftUI

/// AppKit delivers the first mouse-down immediately, without waiting to decide
/// whether it belongs to a double-click gesture.
final class ImmediateRowClickView: NSView {
    var onClick: (Int) -> Void
    var onHover: (Bool) -> Void
    private var hoverArea: NSTrackingArea?

    init(onClick: @escaping (Int) -> Void, onHover: @escaping (Bool) -> Void = { _ in }) {
        self.onClick = onClick
        self.onHover = onHover
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick(event.clickCount)
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

struct ImmediateRowClickSurface: NSViewRepresentable {
    var onClick: (Int) -> Void
    var onHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> ImmediateRowClickView {
        ImmediateRowClickView(onClick: onClick, onHover: onHover)
    }

    func updateNSView(_ view: ImmediateRowClickView, context: Context) {
        view.onClick = onClick
        view.onHover = onHover
    }
}

/// The optional type detail remains selectable while its mouse-down follows
/// the same immediate row-selection path as the rest of the clipping.
final class SelectableTypeField: NSTextField {
    var onClick: (Int) -> Void = { _ in }

    override func mouseDown(with event: NSEvent) {
        onClick(event.clickCount)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
}

struct SelectableTypeLabel: NSViewRepresentable {
    let text: String
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> SelectableTypeField {
        let field = SelectableTypeField(labelWithString: text)
        field.isSelectable = true
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.onClick = onClick
        return field
    }

    func updateNSView(_ field: SelectableTypeField, context: Context) {
        field.stringValue = text
        field.onClick = onClick
    }
}
