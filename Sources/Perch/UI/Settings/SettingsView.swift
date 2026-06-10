import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var services: AppServices

    var body: some View {
        TabView {
            widgetsTab
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(12)
        .frame(minWidth: 460, minHeight: 420)
    }

    private var widgetsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            WidgetPickerView(state: state, surface: .collapsed, title: "Collapsed island")
            WidgetPickerView(state: state, surface: .expanded, title: "Expanded panel")
            Picker("Media source", selection: $state.mediaSourceMode) {
                ForEach(MediaSourceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if state.mediaSourceMode == .universal {
                HStack {
                    Image(systemName: state.mediaRemoteAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.mediaRemoteAvailable ? .green : .orange)
                    Text(state.mediaRemoteAvailable
                         ? "MediaRemote adapter is available."
                         : "MediaRemote adapter not found — falls back to Music/Spotify.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var permissionsTab: some View {
        Form {
            permissionRow("Calendar", granted: services.calendar.accessGranted) {
                services.calendar.requestAccess()
            }
            permissionRow("Notifications", granted: services.agentNotifications.isAuthorized) {
                services.agentNotifications.requestAuthorization()
            }
            if MenuBarRevealService.isSupported {
                permissionRow("Screen Recording (Menu Bar Reveal)", granted: services.menuBarReveal.screenRecordingGranted) {
                    services.menuBarReveal.requestScreenRecording()
                }
            }
            Text("Automation for Music/Spotify is requested when you first use media controls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $state.launchAtLogin)
                .onChange(of: state.launchAtLogin) { on in
                    LaunchAtLoginHelper.setEnabled(on)
                }
            if state.menuBarRevealEnabled {
                Toggle("Show menu bar reveal on hover", isOn: Binding(
                    get: { services.menuBarReveal.revealOnHover },
                    set: { services.menuBarReveal.revealOnHover = $0 }
                ))
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perch")
                .font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                .foregroundStyle(.secondary)
            Text("Dynamic Island for your MacBook notch.")
            Link("Install agent hooks", destination: URL(string: "https://github.com/nshamsiddin/Perch#ai-agents-claude-code--cursor")!)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: action)
            }
        }
    }
}

enum LaunchAtLoginHelper {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                try? service.register()
            } else {
                try? service.unregister()
            }
        }
    }

    static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
