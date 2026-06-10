import CoreGraphics

/// Pure geometry helper translating a `NotchGeometry` into window / shape rects.
/// Shared by the AppKit window (hit-testing, tracking) and the SwiftUI views (drawing),
/// so both agree on exact pixel positions.
struct IslandLayout {
    let geometry: NotchGeometry

    // The enabled features drive how the panel composes itself: a full now-playing row, a slim
    // battery-only strip, or no content row at all.
    var mediaEnabled: Bool = true
    var batteryEnabled: Bool = true

    /// Whether the expanded panel reserves its top now-playing/battery row at all.
    var showsContentRow: Bool { mediaEnabled || batteryEnabled }

    /// True when no feature contributes top content — the panel shows a minimal idle line.
    var isIdle: Bool { !mediaEnabled && !batteryEnabled }

    // Expanded panel dimensions. Height reserves the notch strip up top, then leaves room for
    // a content row below it, so nothing sits behind the camera housing.
    var expandedWidth: CGFloat { max(540, geometry.notchWidth + 320) }

    /// Height of the slim strip when only the battery chip is shown (no now-playing cell).
    var batteryOnlyRowHeight: CGFloat { 40 }

    /// Height of the idle line shown when every feature is off and no agents are active.
    var idleRowHeight: CGFloat { 52 }

    /// Top content-row height: full when media is on, a slim strip for battery-only, else none.
    var contentRowHeight: CGFloat {
        if mediaEnabled { return 66 }
        if batteryEnabled { return batteryOnlyRowHeight }
        return 0
    }

    // The panel floats inside a slightly larger window; these margins keep room around it for the
    // drop shadow and inset it from the window edges. (Top hugs the notch, so no top margin.)
    var windowMarginX: CGFloat { 12 }
    var windowMarginBottom: CGFloat { 14 }

    /// Breathing room inside the panel, below the last row of content, so it never sits flush
    /// against the rounded bottom edge.
    var panelBottomPadding: CGFloat { 12 }

    /// Horizontal padding inside pill-shaped chips (e.g. the battery capsule). Also used as the
    /// agents section's trailing inset so right-aligned text optically lines up with the chip's
    /// text rather than its outer edge.
    var chipHorizontalPadding: CGFloat { 9 }

    /// Expanded height with no agents — the now-playing + battery panel as it was originally.
    /// Includes the in-panel bottom padding plus the window's bottom margin.
    var baseExpandedHeight: CGFloat {
        geometry.notchHeight + contentRowHeight + panelBottomPadding + windowMarginBottom
    }

    // MARK: AI Agents section metrics
    // Shared by the layout math (window size, hit rects) and the SwiftUI `AgentsSectionView`, so
    // the reserved/visible heights and the rendered content always agree.
    // When a content row sits above, this space holds the divider; when the agents list is the
    // panel's first section (no content row), it's plain breathing room below the notch instead.
    var agentsSectionTopInset: CGFloat { showsContentRow ? 8 : 14 }
    var agentsHeaderHeight: CGFloat { 34 }
    var agentRowHeight: CGFloat { 30 }
    /// Taller variant for a row blocking on an approval: it adds a second line carrying the
    /// Approve/Deny buttons and an optional steering-note field.
    var agentApprovalRowHeight: CGFloat { 64 }
    var agentsMoreLineHeight: CGFloat { 16 }
    var agentsRowsMax: Int { 3 }
    /// Max height for the scrollable overflow list when "+N more" is expanded.
    var agentsOverflowScrollMaxHeight: CGFloat {
        CGFloat(agentsRowsMax + 1) * agentRowHeight + agentsMoreLineHeight
    }

    /// Height of the agents block for a given active-session count (0 when none). `approvalCount` is
    /// how many of those rows are blocking on an approval (they float to the top and are taller).
    /// The "Agents" title + status pills live in the reserved notch strip (see `ExpandedView`), so
    /// this section reserves only the rows themselves — no in-section header height.
    func agentsSectionHeight(sessionCount: Int, approvalCount: Int = 0, overflowExpanded: Bool = false) -> CGFloat {
        guard sessionCount > 0 else { return 0 }
        let hasOverflow = sessionCount > agentsRowsMax
        let rows: Int
        if overflowExpanded && hasOverflow {
            rows = min(sessionCount, agentsRowsMax + 2)
        } else {
            rows = min(sessionCount, agentsRowsMax)
        }
        let approvals = min(max(approvalCount, 0), rows)
        let normal = rows - approvals
        let more: CGFloat = hasOverflow ? agentsMoreLineHeight : 0
        let scrollExtra: CGFloat = (overflowExpanded && hasOverflow)
            ? agentsOverflowScrollMaxHeight - CGFloat(min(sessionCount, agentsRowsMax)) * agentRowHeight
            : 0
        return agentsSectionTopInset
            + CGFloat(approvals) * agentApprovalRowHeight
            + CGFloat(normal) * agentRowHeight + more + scrollExtra
    }

    /// The window always reserves room for the *largest* agents section (incl. the "+N more" line),
    /// worst-cased to every visible row being a taller approval row, so the panel can grow to show
    /// approvals without ever resizing the window.
    var expandedHeight: CGFloat {
        baseExpandedHeight + agentsSectionHeight(sessionCount: agentsRowsMax + 1,
                                                 approvalCount: agentsRowsMax + 1)
    }

    /// Visible expanded-panel height for the current number of active agents. When every feature
    /// is off and no agents are active, the panel shows a minimal idle line, so reserve its height.
    func expandedVisibleHeight(sessionCount: Int, approvalCount: Int = 0) -> CGFloat {
        var height = baseExpandedHeight + agentsSectionHeight(sessionCount: sessionCount,
                                                              approvalCount: approvalCount)
        if isIdle && sessionCount == 0 { height += idleRowHeight }
        return height
    }

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

    /// Expanded panel rect in the window's local (bottom-left origin) coordinates. Spans the full
    /// reserved window height; used as the stable hover-tracking region.
    var expandedRect: CGRect {
        CGRect(
            x: 0,
            y: windowSize.height - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
    }

    /// Visible expanded-panel rect for the current agent count, top-aligned in the window. Used
    /// as the stable hover-tracking region while expanded.
    func expandedVisibleRect(sessionCount: Int, approvalCount: Int = 0) -> CGRect {
        let h = expandedVisibleHeight(sessionCount: sessionCount, approvalCount: approvalCount)
        return CGRect(
            x: 0,
            y: windowSize.height - h,
            width: expandedWidth,
            height: h
        )
    }

    /// Clickable expanded panel — inset from `expandedVisibleRect` by the window margins so
    /// transparent side/bottom strips (shadow room) pass clicks to apps behind the overlay.
    func expandedInteractiveRect(sessionCount: Int, approvalCount: Int = 0) -> CGRect {
        let h = expandedVisibleHeight(sessionCount: sessionCount, approvalCount: approvalCount)
        return CGRect(
            x: windowMarginX,
            y: windowSize.height - h,
            width: expandedWidth - 2 * windowMarginX,
            height: h - windowMarginBottom
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
