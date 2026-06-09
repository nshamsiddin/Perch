import Foundation
import UserNotifications

/// Posts a Notification Center alert (with sound) when an agent starts waiting for input, so you
/// can step away from the notch and still be pulled back. Tapping the notification refocuses the
/// agent's terminal/editor via the `onActivate` callback.
///
/// Authorization is requested lazily the first time an alert would fire, so users who keep the
/// feature off are never prompted.
final class AgentNotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// Called with a session id when a notification is tapped.
    var onActivate: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var authorized = false
    private var requestedAuth = false

    /// Wire up as the delegate. Safe even if notifications are never used.
    func start() {
        center.delegate = self
    }

    /// Posts a "waiting" alert for the session. Requests authorization on first use.
    func notifyWaiting(_ session: AgentSession) {
        ensureAuthorized { [weak self] granted in
            guard granted, let self else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(session.tool.label) needs input"
            content.body = session.activity ?? "Waiting in \(session.project)"
            content.sound = .default
            content.userInfo = ["sessionID": session.id]
            // Stable identifier per session so repeat waits replace rather than stack up.
            let request = UNNotificationRequest(
                identifier: "agent-waiting-\(session.id)",
                content: content,
                trigger: nil
            )
            self.center.add(request)
        }
    }

    private func ensureAuthorized(_ completion: @escaping (Bool) -> Void) {
        if authorized { completion(true); return }
        // Avoid hammering the prompt; request once, then read settings thereafter.
        center.getNotificationSettings { [weak self] settings in
            guard let self else { completion(false); return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.authorized = true
                completion(true)
            case .notDetermined where !self.requestedAuth:
                self.requestedAuth = true
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    self.authorized = granted
                    completion(granted)
                }
            default:
                completion(false)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner + play sound even when Islet is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Tapping the notification refocuses the agent.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let sessionID = response.notification.request.content.userInfo["sessionID"] as? String {
            DispatchQueue.main.async { [weak self] in self?.onActivate?(sessionID) }
        }
        completionHandler()
    }
}
