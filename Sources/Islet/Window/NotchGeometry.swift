import AppKit

/// Geometry describing the notch (or a synthetic pill on non-notch Macs) on a given screen.
struct NotchGeometry: Equatable {
    /// Full frame of the target screen, in AppKit (bottom-left origin) coordinates.
    var screenFrame: CGRect
    /// Width of the physical notch, or the synthetic pill width on non-notch Macs.
    var notchWidth: CGFloat
    /// Height of the notch hot-zone (menu-bar height around the notch).
    var notchHeight: CGFloat
    /// Whether the target screen actually has a hardware notch.
    var hasNotch: Bool

    /// Conservative fallback used before the first screen resolve.
    static let fallback = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        notchWidth: 200,
        notchHeight: 32,
        hasNotch: false
    )

    /// Resolve geometry for the built-in (notched) display, falling back to the main screen.
    static func resolve() -> NotchGeometry {
        let screen = builtInNotchedScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return .fallback }

        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0

        let notchHeight: CGFloat = hasNotch ? topInset : max(NSStatusBar.system.thickness, 24)

        let notchWidth: CGFloat
        if hasNotch {
            // There is no direct notch-width API: derive it from the auxiliary areas
            // flanking the camera housing.
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            let derived = frame.width - leftWidth - rightWidth
            notchWidth = derived > 0 ? derived : 200
        } else {
            notchWidth = 200 // synthetic centered pill
        }

        return NotchGeometry(
            screenFrame: frame,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            hasNotch: hasNotch
        )
    }

    /// The first screen reporting a non-zero top safe-area inset is the built-in notched display.
    private static func builtInNotchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }
}
