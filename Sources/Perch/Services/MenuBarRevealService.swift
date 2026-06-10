import AppKit
import CoreGraphics

/// Ice Bar MVP: spacer status items hide clutter; hovering the menu bar reveals a strip below the island.
final class MenuBarRevealService {
    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private let state: IslandState
    private var leftSpacer: NSStatusItem?
    private var rightSpacer: NSStatusItem?
    private var globalMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    var revealOnHover = true

    var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    init(state: IslandState) {
        self.state = state
    }

    func start() {
        guard Self.isSupported, state.menuBarRevealEnabled else { return }
        installSpacers()
        installHoverMonitor()
    }

    func stop() {
        hideWorkItem?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        leftSpacer = nil
        rightSpacer = nil
        state.menuBarRevealActive = false
        state.menuBarRevealItems = []
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    private func installSpacers() {
        let hiddenWidth = CGFloat(UserDefaults.standard.double(forKey: "menuBarReveal.hiddenWidth"))
        let width = hiddenWidth > 0 ? hiddenWidth : 280
        leftSpacer = NSStatusBar.system.statusItem(withLength: width)
        rightSpacer = NSStatusBar.system.statusItem(withLength: width)
        leftSpacer?.button?.alphaValue = 0.001
        rightSpacer?.button?.alphaValue = 0.001
    }

    private func installHoverMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard revealOnHover else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }
        let loc = NSEvent.mouseLocation
        let nearMenuBar = loc.y >= frame.maxY - 4
        if nearMenuBar {
            reveal()
        } else if !state.menuBarRevealActive {
            return
        } else {
            scheduleHide()
        }
    }

    private func reveal() {
        hideWorkItem?.cancel()
        guard !state.menuBarRevealActive else { return }
        captureMenuBarItems()
        state.menuBarRevealActive = true
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.state.menuBarRevealActive = false
            self?.state.menuBarRevealItems = []
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func captureMenuBarItems() {
        guard screenRecordingGranted, let screen = NSScreen.main else {
            state.menuBarRevealItems = [
                MenuBarRevealItem(id: "hint", title: "Grant Screen Recording to preview hidden items", imageData: nil)
            ]
            return
        }
        let menuBarHeight = NSStatusBar.system.thickness
        let rect = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            return
        }
        let item = MenuBarRevealItem(id: "capture", title: "Menu bar", imageData: image.png)
        state.menuBarRevealItems = [item]
    }
}

private extension CGImage {
    var png: Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }
}
