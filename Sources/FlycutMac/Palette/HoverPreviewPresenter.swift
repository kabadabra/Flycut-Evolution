import AppKit
import SwiftUI
import FlycutCore

/// The palette owns dismissal so a mouse-down in a clipping row reaches that
/// row even while its preview is visible.
@MainActor final class HoverPreviewPresenter {
    let popover = NSPopover()

    init() {
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 368, height: 390)
    }

    func show(_ clip: Clip, images: ImagePreviewModel, beside anchor: NSView, onHover: @escaping (Bool) -> Void) {
        guard anchor.window != nil else { return }
        let content = AnyView(ClippingPreview(clip: clip, images: images).onHover(perform: onHover))
        if let controller = popover.contentViewController as? NSHostingController<AnyView> {
            controller.rootView = content
        } else {
            popover.contentViewController = NSHostingController(rootView: content)
        }
        if !popover.isShown {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        }
    }

    func close() { popover.close() }
}

@MainActor private final class HoverPreviewAnchorView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}

struct HoverPreviewAnchor: NSViewRepresentable {
    let clip: Clip
    let isPresented: Bool
    let images: ImagePreviewModel
    let onHover: (Bool) -> Void

    @MainActor final class Coordinator {
        let presenter = HoverPreviewPresenter()
        var clip: Clip?
        var images: ImagePreviewModel?
        var onHover: (Bool) -> Void = { _ in }

        func refresh(in view: NSView) {
            guard view.window != nil else { presenter.close(); return }
            if let clip, let images { presenter.show(clip, images: images, beside: view, onHover: onHover) }
            else { presenter.close() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = HoverPreviewAnchorView()
        let coordinator = context.coordinator
        view.onWindowChange = { [weak view] in
            if let view { coordinator.refresh(in: view) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.clip = isPresented ? clip : nil
        context.coordinator.images = images
        context.coordinator.onHover = onHover
        context.coordinator.refresh(in: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        (view as? HoverPreviewAnchorView)?.onWindowChange = nil
        coordinator.presenter.close()
    }
}
