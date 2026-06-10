import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var services: AppServices!
    private var windowController: NotchWindowController!
    private var fullScreenObserver: FullScreenObserver!
    private var statusItem: NSStatusItem!
    private var energyModeMenu: NSMenu!
    private var mediaToggleItem: NSMenuItem!
    private var batteryToggleItem: NSMenuItem!
    private var agentsToggleItem: NSMenuItem!
    private var notifyToggleItem: NSMenuItem!
    private var controlToggleItem: NSMenuItem!
    private var controlMenuItem: NSMenuItem!
    private var controlSubmenu: NSMenu!
    private var pause15Item: NSMenuItem!
    private var pause1hItem: NSMenuItem!
    private var pauseRestartItem: NSMenuItem!
    private var resumeGatingItem: NSMenuItem!
    private var recentDecisionsItem: NSMenuItem!
    private var removeHelperItem: NSMenuItem!
    private var auditWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let updateService = UpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = AppServices(state: state)
        windowController = NotchWindowController(state: state, services: services)

        setupStatusItem()

        fullScreenObserver = FullScreenObserver { [weak self] isFullScreen in
            self?.windowController.setHiddenForFullScreen(isFullScreen)
        }
        fullScreenObserver.start()

        services.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
        fullScreenObserver.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                   accessibilityDescription: "Perch")
        }

        let menu = NSMenu()
        // Refresh the feature checkmarks each time the menu opens so they reflect live state.
        menu.delegate = self
        let header = NSMenuItem(title: "Perch", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let featuresHeader = NSMenuItem(title: "Features", action: nil, keyEquivalent: "")
        featuresHeader.isEnabled = false
        menu.addItem(featuresHeader)

        mediaToggleItem = NSMenuItem(title: "Media", action: #selector(toggleMedia), keyEquivalent: "")
        batteryToggleItem = NSMenuItem(title: "Battery", action: #selector(toggleBattery), keyEquivalent: "")
        agentsToggleItem = NSMenuItem(title: "AI Agents", action: #selector(toggleAgents), keyEquivalent: "")
        for item in [mediaToggleItem!, batteryToggleItem!, agentsToggleItem!] {
            item.target = self
            menu.addItem(item)
        }
        // Sub-option of AI Agents: an alert + sound when an agent starts waiting for input.
        notifyToggleItem = NSMenuItem(title: "Notify on waiting",
                                      action: #selector(toggleNotify), keyEquivalent: "")
        notifyToggleItem.target = self
        notifyToggleItem.indentationLevel = 1
        menu.addItem(notifyToggleItem)
        // Sub-option of AI Agents: Control submenu (toggle + gating snooze).
        controlMenuItem = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        controlSubmenu = NSMenu(title: "Control")
        controlSubmenu.delegate = self
        controlToggleItem = NSMenuItem(title: "Approve / deny / stop",
                                       action: #selector(toggleControl), keyEquivalent: "")
        controlToggleItem.target = self
        controlSubmenu.addItem(controlToggleItem)
        controlSubmenu.addItem(.separator())
        pause15Item = NSMenuItem(title: "Pause gating 15 minutes",
                                 action: #selector(pauseGating15m), keyEquivalent: "")
        pause1hItem = NSMenuItem(title: "Pause gating 1 hour",
                                 action: #selector(pauseGating1h), keyEquivalent: "")
        pauseRestartItem = NSMenuItem(title: "Pause until restart",
                                      action: #selector(pauseGatingUntilRestart), keyEquivalent: "")
        resumeGatingItem = NSMenuItem(title: "Resume gating",
                                      action: #selector(resumeGating), keyEquivalent: "")
        for item in [pause15Item!, pause1hItem!, pauseRestartItem!, resumeGatingItem!] {
            item.target = self
            controlSubmenu.addItem(item)
        }
        controlMenuItem.submenu = controlSubmenu
        controlMenuItem.indentationLevel = 1
        menu.addItem(controlMenuItem)
        recentDecisionsItem = NSMenuItem(title: "Recent decisions…",
                                         action: #selector(showRecentDecisions), keyEquivalent: "")
        recentDecisionsItem.target = self
        recentDecisionsItem.indentationLevel = 1
        menu.addItem(recentDecisionsItem)
        updateFeatureChecks()
        menu.addItem(.separator())

        let energyItem = NSMenuItem(title: "Energy Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Energy Mode")
        // Refresh checkmarks each time the submenu opens by reading the live mode.
        submenu.delegate = self
        for mode in PowerModeService.PowerMode.allCases {
            let modeItem = NSMenuItem(title: mode.title,
                                      action: #selector(selectEnergyMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.tag = mode.rawValue
            submenu.addItem(modeItem)
        }
        // Teardown for the privileged helper the Energy Mode install creates. Hidden unless the
        // helper is actually installed (visibility refreshed in `menuNeedsUpdate`).
        submenu.addItem(.separator())
        removeHelperItem = NSMenuItem(title: "Remove Perch helper",
                                      action: #selector(removeEnergyHelper), keyEquivalent: "")
        removeHelperItem.target = self
        removeHelperItem.isHidden = true
        submenu.addItem(removeHelperItem)
        energyItem.submenu = submenu
        energyModeMenu = submenu
        menu.addItem(energyItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…",
                                action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Perch",
                                action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func selectEnergyMode(_ sender: NSMenuItem) {
        guard let mode = PowerModeService.PowerMode(rawValue: sender.tag) else { return }
        services.powerMode.setMode(mode) { [weak self] current in
            self?.updateEnergyModeChecks(current)
        }
    }

    private func updateEnergyModeChecks(_ current: PowerModeService.PowerMode) {
        guard let menu = energyModeMenu else { return }
        for item in menu.items {
            item.state = (item.tag == current.rawValue) ? .on : .off
        }
    }

    /// Removes the privileged Energy Mode helper (one admin prompt), then refreshes the submenu.
    @objc private func removeEnergyHelper() {
        services.powerMode.removeHelper { [weak self] _ in
            guard let self else { return }
            self.updateEnergyModeChecks(self.services.powerMode.currentMode())
        }
    }

    // MARK: - Feature toggles

    @objc private func toggleMedia() {
        state.setWidgetEnabled(.media, enabled: !state.mediaEnabled, surface: .both)
        updateFeatureChecks()
    }

    @objc private func toggleBattery() {
        state.setWidgetEnabled(.battery, enabled: !state.batteryEnabled, surface: .both)
        updateFeatureChecks()
    }

    @objc private func toggleAgents() {
        state.setWidgetEnabled(.agents, enabled: !state.agentsEnabled, surface: .both)
        updateFeatureChecks()
    }

    @objc private func toggleNotify() {
        state.notifyOnWaiting.toggle()
        updateFeatureChecks()
    }

    @objc private func toggleControl() {
        state.agentsControlEnabled.toggle()
        updateFeatureChecks()
    }

    @objc private func pauseGating15m() {
        services.pauseGating(until: Date().addingTimeInterval(15 * 60))
        updateFeatureChecks()
    }

    @objc private func pauseGating1h() {
        services.pauseGating(until: Date().addingTimeInterval(60 * 60))
        updateFeatureChecks()
    }

    @objc private func pauseGatingUntilRestart() {
        services.pauseGating(until: AgentCommandService.gatingPausedIndefinite)
        updateFeatureChecks()
    }

    @objc private func resumeGating() {
        services.resumeGating()
        updateFeatureChecks()
    }

    @objc private func showSettings() {
        let view = SettingsView(state: state, services: services)
        let controller = NSHostingController(rootView: view)
        if let settingsWindow {
            settingsWindow.contentViewController = controller
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: controller)
        window.title = "Perch Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showRecentDecisions() {
        let entries = services.agentAudit.recentEntries()
        let view = AgentAuditView(entries: entries)
        let controller = NSHostingController(rootView: view)
        if let auditWindow {
            auditWindow.contentViewController = controller
            auditWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: controller)
        window.title = "Perch — Recent decisions"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 360, height: 320))
        window.center()
        window.isReleasedWhenClosed = false
        auditWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateFeatureChecks() {
        mediaToggleItem?.state = state.mediaEnabled ? .on : .off
        batteryToggleItem?.state = state.batteryEnabled ? .on : .off
        agentsToggleItem?.state = state.agentsEnabled ? .on : .off
        notifyToggleItem?.state = state.notifyOnWaiting ? .on : .off
        controlToggleItem?.state = state.agentsControlEnabled ? .on : .off
        // The agent sub-options only apply while AI Agents is on.
        notifyToggleItem?.isEnabled = state.agentsEnabled
        controlToggleItem?.isEnabled = state.agentsEnabled
        let controlOn = state.agentsEnabled && state.agentsControlEnabled
        pause15Item?.isEnabled = controlOn
        pause1hItem?.isEnabled = controlOn
        pauseRestartItem?.isEnabled = controlOn
        resumeGatingItem?.isEnabled = controlOn && state.isGatingPaused
        recentDecisionsItem?.isEnabled = state.agentsEnabled
        // Subtle paused indicator on the Control parent menu title.
        if state.isGatingPaused {
            let indefinite = state.gatingPausedUntil == AgentCommandService.gatingPausedIndefinite
            controlMenuItem?.title = indefinite ? "Control (gating paused)" : "Control (paused)"
        } else {
            controlMenuItem?.title = "Control"
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateService.checkForUpdates(sender)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === energyModeMenu {
            updateEnergyModeChecks(services.powerMode.currentMode())
            // Only offer the teardown when the helper is actually present.
            removeHelperItem?.isHidden = !services.powerMode.isHelperInstalled()
        } else if menu === controlSubmenu {
            updateFeatureChecks()
        } else {
            updateFeatureChecks()
        }
    }
}
