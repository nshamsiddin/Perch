import CoreGraphics

/// Pure geometry helper translating a `NotchGeometry` into window / shape rects.
/// Shared by the AppKit window (hit-testing, tracking) and the SwiftUI views (drawing),
/// so both agree on exact pixel positions.
struct IslandLayout {
    let geometry: NotchGeometry

    // Expanded panel dimensions. Height reserves the notch strip up top, then leaves room for
    // a content row below it, so nothing sits behind the camera housing.
    var expandedWidth: CGFloat { max(540, geometry.notchWidth + 320) }
    var contentRowHeight: CGFloat { 66 }
    var expandedHeight: CGFloat { geometry.notchHeight + contentRowHeight + 14 }

    /// Width of a single now-playing "ear" flanking the notch while collapsed. Shared by the
    /// SwiftUI compact view and the AppKit hit/hover rects so visuals and interaction line up.
    var earWidth: CGFloat { 46 }

    /// Total width of the now-playing compact pill (an ear on each side of the notch).
    var compactWidth: CGFloat { geometry.notchWidth + 2 * earWidth }

    /// Window covers the top-center region large enough for the expanded panel.
    var windowSize: CGSize { CGSize(width: expandedWidth, height: expandedHeight) }

    /// Window origin in screen coordinates (top-aligned, horizontally centered on the notch screen).
    var windowOrigin: CGPoint {
        CGPoint(
            x: geometry.screenFrame.midX - windowSize.width / 2,
            y: geometry.screenFrame.maxY - windowSize.height
        )
    }

    var windowFrame: CGRect { CGRect(origin: windowOrigin, size: windowSize) }

    /// Collapsed pill rect (bare notch width) in the window's local (bottom-left origin) coords.
    var collapsedRect: CGRect { collapsedRect(width: geometry.notchWidth) }

    /// Collapsed pill rect for an arbitrary visual width, top-aligned and centered on the notch.
    /// Used so wider collapsed presentations (now-playing ears, peek) stay click/hover-able.
    func collapsedRect(width: CGFloat) -> CGRect {
        let h = geometry.notchHeight
        return CGRect(
            x: (windowSize.width - width) / 2,
            y: windowSize.height - h,
            width: width,
            height: h
        )
    }

    /// Expanded panel rect in the window's local (bottom-left origin) coordinates.
    var expandedRect: CGRect {
        CGRect(
            x: 0,
            y: windowSize.height - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
    }

    /// Hot-zone used for hover detection while collapsed: slightly wider/taller than the
    /// pill so the cursor reliably enters it.
    var hoverHotZone: CGRect { hoverHotZone(width: geometry.notchWidth) }

    /// Hover hot-zone for a given collapsed visual width.
    func hoverHotZone(width: CGFloat) -> CGRect {
        collapsedRect(width: width).insetBy(dx: -6, dy: -2)
    }
}
