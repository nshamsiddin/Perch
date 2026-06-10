import SwiftUI

struct WidgetPickerView: View {
    @ObservedObject var state: IslandState
    let surface: IslandState.WidgetSurface
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            List {
                ForEach(IslandWidget.available) { widget in
                    Toggle(isOn: binding(for: widget)) {
                        Label(widget.label, systemImage: widget.symbol)
                    }
                    .disabled(widget == .menuBarReveal && !MenuBarRevealService.isSupported)
                }
                .onMove(perform: move)
            }
            .frame(minHeight: 180)
        }
    }

    private func binding(for widget: IslandWidget) -> Binding<Bool> {
        Binding(
            get: { isOn(widget) },
            set: { state.setWidgetEnabled(widget, enabled: $0, surface: surface) }
        )
    }

    private func isOn(_ widget: IslandWidget) -> Bool {
        switch surface {
        case .collapsed: return state.collapsedWidgetOrder.contains(widget)
        case .expanded:  return state.expandedWidgetOrder.contains(widget)
        case .both:
            return state.collapsedWidgetOrder.contains(widget) || state.expandedWidgetOrder.contains(widget)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        switch surface {
        case .collapsed:
            var order = state.collapsedWidgetOrder
            order.move(fromOffsets: source, toOffset: destination)
            state.collapsedWidgetOrder = order
        case .expanded:
            var order = state.expandedWidgetOrder
            order.move(fromOffsets: source, toOffset: destination)
            state.expandedWidgetOrder = order
        case .both:
            break
        }
    }
}
