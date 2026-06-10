import Foundation

/// Persists widget order and membership in UserDefaults.
enum WidgetPreferences {
    private static let collapsedKey = "widgets.collapsed.order"
    private static let expandedKey = "widgets.expanded.order"

    static func loadCollapsed() -> [IslandWidget] {
        loadOrder(key: collapsedKey, default: IslandWidget.defaultCollapsed)
    }

    static func loadExpanded() -> [IslandWidget] {
        loadOrder(key: expandedKey, default: IslandWidget.defaultExpanded)
    }

    static func saveCollapsed(_ widgets: [IslandWidget]) {
        saveOrder(widgets, key: collapsedKey)
    }

    static func saveExpanded(_ widgets: [IslandWidget]) {
        saveOrder(widgets, key: expandedKey)
    }

    static func isEnabled(_ widget: IslandWidget, collapsed: [IslandWidget], expanded: [IslandWidget]) -> Bool {
        collapsed.contains(widget) || expanded.contains(widget)
    }

    private static func loadOrder(key: String, default defaultOrder: [IslandWidget]) -> [IslandWidget] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultOrder
        }
        let parsed = raw.compactMap { IslandWidget(rawValue: $0) }
        return parsed.isEmpty ? defaultOrder : parsed
    }

    private static func saveOrder(_ widgets: [IslandWidget], key: String) {
        let raw = widgets.map(\.rawValue)
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
