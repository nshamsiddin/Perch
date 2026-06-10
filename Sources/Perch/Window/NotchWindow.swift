import AppKit

/// Borderless, transparent, always-on-top window that floats over the notch.
final class NotchWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Draw around the notch, above the menu bar. `CGShieldingWindowLevel` reliably sits
        // above the menu bar (plain `.statusBar` can render below it on some configurations).
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        // Clicks land on the island shape only; transparent regions pass through via hit-testing.
    }

    // Borderless windows are non-key by default; allow key so SwiftUI controls receive clicks.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
