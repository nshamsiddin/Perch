import AppKit
import SwiftUI

/// SwiftUI host that accepts first mouse so buttons fire on the first click while the overlay
/// window is inactive. `acceptsFirstMouse` on the outer container does not help — hit-testing
/// lands on the hosting view, not its superview.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// NSHostingView fills the oversized overlay window; only the island shape should claim hits.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let container = superview as? IslandContainerView,
              let controller = container.controller else { return nil }
        let pointInContainer = container.convert(point, from: self)
        guard controller.currentInteractiveRect().contains(pointInContainer) else { return nil }
        return super.hitTest(point)
    }
}

/// Hosts the SwiftUI island and implements two AppKit behaviors SwiftUI can't do alone:
///   1. Click-through: hit-testing only claims points inside the current island shape,
///      so transparent regions pass clicks to the apps below.
///   2. Hover detection via an `NSTrackingArea` with `.activeAlways` (fires even when the
///      app is inactive, with no Accessibility permission).
///
/// A single, stable tracking area covers the whole top region; `mouseMoved` then checks
/// hot-zone membership. This avoids re-adding tracking areas on every expand/collapse,
/// which can emit spurious enter/exit events.
final class IslandContainerView: NSView {
    weak var controller: NotchWindowController?

    override var isFlipped: Bool { false } // bottom-left origin to match layout math

    /// Perch is an accessory (menu-bar) app with a borderless overlay window. Without this, the
    /// first click is swallowed keying the window and SwiftUI buttons (agent rows, media) never fire.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller else { return nil }
        let activeRect = controller.currentInteractiveRect()
        return activeRect.contains(point) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }

        guard let controller else { return }
        let area = NSTrackingArea(
            rect: controller.currentHoverRect(),
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.handleMouseMoved(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.handleMouseMoved(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        controller?.handleHoverExit()
    }
}
