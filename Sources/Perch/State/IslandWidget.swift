import Foundation

/// A configurable island widget. Membership in `collapsedWidgets` / `expandedWidgets` enables it.
enum IslandWidget: String, Codable, CaseIterable, Identifiable, Hashable {
    case media
    case battery
    case agents
    case calendar
    case privacy
    case clock
    case menuBarReveal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .media:          return "Media"
        case .battery:        return "Battery"
        case .agents:         return "AI Agents"
        case .calendar:       return "Calendar"
        case .privacy:        return "Privacy"
        case .clock:          return "Clock"
        case .menuBarReveal:  return "Menu Bar Reveal"
        }
    }

    var symbol: String {
        switch self {
        case .media:          return "music.note"
        case .battery:        return "battery.100"
        case .agents:         return "chevron.left.forwardslash.chevron.right"
        case .calendar:       return "calendar"
        case .privacy:        return "eye.trianglebadge.exclamationmark"
        case .clock:          return "clock"
        case .menuBarReveal:  return "menubar.rectangle"
        }
    }

    /// Widgets available on the current OS (menu bar reveal requires macOS 14+).
    static var available: [IslandWidget] {
        if #available(macOS 14.0, *) {
            return Array(allCases)
        }
        return allCases.filter { $0 != .menuBarReveal }
    }

    static let defaultCollapsed: [IslandWidget] = [.agents, .media]
    static let defaultExpanded: [IslandWidget] = [.agents, .media, .battery]
}
