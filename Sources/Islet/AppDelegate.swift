import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var services: AppServices!
    private var windowController: NotchWindowController!
    private var fullScreenObserver: FullScreenObserver!
    private var statusItem: NSStatusItem!
    private var energyModeMenu: NSMenu!

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
                                   accessibilityDescription: "Islet")
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "Islet", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
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
        energyItem.submenu = submenu
        energyModeMenu = submenu
        menu.addItem(energyItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Islet",
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === energyModeMenu else { return }
        updateEnergyModeChecks(services.powerMode.currentMode())
    }
}
