import AppKit
import EventKit
import Foundation

/// Surfaces the next upcoming calendar event for island peeks and countdown ears.
final class CalendarService {
    private let state: IslandState
    private let activity: ActivityCenter
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var lastPeekKey = ""

    var accessGranted: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    init(state: IslandState, activity: ActivityCenter) {
        self.state = state
        self.activity = activity
    }

    func start() {
        guard state.calendarEnabled else { return }
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        state.nextCalendarEvent = nil
    }

    func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                if granted { self?.start() }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                if granted { self?.start() }
            }
        }
    }

    func refresh() {
        guard accessGranted else {
            state.nextCalendarEvent = nil
            return
        }
        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        guard let next = events.first else {
            state.nextCalendarEvent = nil
            return
        }
        let mapped = CalendarEvent(
            title: next.title,
            start: next.startDate,
            end: next.endDate,
            location: next.location,
            eventIdentifier: next.eventIdentifier,
            url: next.url
        )
        state.nextCalendarEvent = mapped
        maybePeek(for: mapped)
    }

    private func maybePeek(for event: CalendarEvent) {
        let minutes = Self.minutesUntil(event.start)
        let key: String
        let symbol: String
        let text: String
        if minutes == 0 {
            key = "start-\(event.eventIdentifier)"
            symbol = "video"
            text = "\(event.title) now"
        } else if minutes == 5 {
            key = "5-\(event.eventIdentifier)"
            symbol = "calendar"
            text = "\(event.title) in 5m"
        } else if minutes == 15 {
            key = "15-\(event.eventIdentifier)"
            symbol = "calendar"
            text = "\(event.title) in 15m"
        } else {
            return
        }
        guard key != lastPeekKey else { return }
        lastPeekKey = key
        activity.show(symbol: symbol, text: text)
    }

    static func minutesUntil(_ start: Date, from now: Date = Date()) -> Int {
        max(0, Int(start.timeIntervalSince(now) / 60))
    }

    func openEvent(_ event: CalendarEvent) {
        if let url = event.url {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: "ical://ekevent/\(event.eventIdentifier)") {
            NSWorkspace.shared.open(url)
        }
    }
}
