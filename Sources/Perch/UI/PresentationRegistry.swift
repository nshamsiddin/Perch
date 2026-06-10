import CoreGraphics
import Foundation

/// Collapsed island presentation slots. Fixed system slots (`volumeHUD`) sit above user-ordered ones.
enum IslandCollapsedPresentation: Equatable {
    case collapsed
    case clock
    case nowPlayingCompact
    case calendarCountdown
    case agentLive
    case peek
    case privacyIndicator
    case volumeHUD
    case expanded
}

/// Resolves which collapsed presentation wins, shared by SwiftUI and AppKit hit-testing.
struct PresentationRegistry {
    let state: IslandState
    let layout: IslandLayout

    /// Fixed precedence above user widget order: expanded, then volume HUD.
    private var fixedSlot: IslandCollapsedPresentation? {
        if state.mode == .expanded { return .expanded }
        if state.volumeHUD != nil { return .volumeHUD }
        return nil
    }

    /// User-ordered default precedence when widgets are not customized.
    private static let defaultSlotOrder: [IslandCollapsedPresentation] = [
        .privacyIndicator,
        .peek,
        .agentLive,
        .calendarCountdown,
        .nowPlayingCompact,
        .clock,
        .collapsed,
    ]

    var presentation: IslandCollapsedPresentation {
        if let fixed = fixedSlot { return fixed }
        for slot in slotOrder {
            if isSlotActive(slot) { return slot }
        }
        return .collapsed
    }

    private var slotOrder: [IslandCollapsedPresentation] {
        var order: [IslandCollapsedPresentation] = []
        for widget in state.collapsedWidgetOrder {
            if let slot = slot(for: widget), !order.contains(slot) {
                order.append(slot)
            }
        }
        for slot in Self.defaultSlotOrder where !order.contains(slot) {
            order.append(slot)
        }
        return order
    }

    func collapsedWidth(notchWidth: CGFloat) -> CGFloat {
        switch presentation {
        case .collapsed:
            return notchWidth
        case .clock:
            return notchWidth + 160
        case .nowPlayingCompact, .agentLive:
            return layout.compactWidth
        case .calendarCountdown:
            return layout.compactWidth
        case .peek:
            return notchWidth + 220
        case .privacyIndicator:
            return layout.compactWidth
        case .volumeHUD:
            return notchWidth + 200
        case .expanded:
            return layout.expandedWidth - 2 * layout.windowMarginX
        }
    }

    func collapsedHeight(notchHeight: CGFloat) -> CGFloat {
        switch presentation {
        case .peek, .volumeHUD:
            return notchHeight + 6
        default:
            return notchHeight
        }
    }

    private func slot(for widget: IslandWidget) -> IslandCollapsedPresentation? {
        switch widget {
        case .media:          return .nowPlayingCompact
        case .agents:         return .agentLive
        case .calendar:       return .calendarCountdown
        case .privacy:        return .privacyIndicator
        case .clock:          return .clock
        case .battery, .menuBarReveal: return nil
        }
    }

    private func isSlotActive(_ slot: IslandCollapsedPresentation) -> Bool {
        switch slot {
        case .collapsed:
            return true
        case .clock:
            return state.clockWidgetEnabled
        case .nowPlayingCompact:
            return state.nowPlayingActive
        case .calendarCountdown:
            return state.calendarCountdownActive
        case .agentLive:
            return state.hasActiveAgents
        case .peek:
            return state.currentActivity != nil
        case .privacyIndicator:
            return state.privacyIndicatorActive
        case .volumeHUD, .expanded:
            return false
        }
    }
}
