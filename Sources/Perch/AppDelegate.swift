import AppKit

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
    private var removeHelperItem: NSMenuItem!

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
        // Sub-option of AI Agents: let the island approve/deny/stop agents (gates Claude tool calls).
        controlToggleItem = NSMenuItem(title: "Control (approve/deny/stop)",
                                       action: #selector(toggleControl), keyEquivalent: "")
        controlToggleItem.target = self
        controlToggleItem.indentationLevel = 1
        menu.addItem(controlToggleItem)
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
        state.mediaEnabled.toggle()
        updateFeatureChecks()
    }

    @objc private func toggleBattery() {
        state.batteryEnabled.toggle()
        updateFeatureChecks()
    }

    @objc private func toggleAgents() {
        state.agentsEnabled.toggle()
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

    private func updateFeatureChecks() {
        mediaToggleItem?.state = state.mediaEnabled ? .on : .off
        batteryToggleItem?.state = state.batteryEnabled ? .on : .off
        agentsToggleItem?.state = state.agentsEnabled ? .on : .off
        notifyToggleItem?.state = state.notifyOnWaiting ? .on : .off
        controlToggleItem?.state = state.agentsControlEnabled ? .on : .off
        // The agent sub-options only apply while AI Agents is on.
        notifyToggleItem?.isEnabled = state.agentsEnabled
        controlToggleItem?.isEnabled = state.agentsEnabled
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
        } else {
            updateFeatureChecks()
        }
    }
}
