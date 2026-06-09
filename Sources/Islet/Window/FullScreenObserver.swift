import AppKit

/// Detects when another app is in full-screen on the notched display so the island can hide
/// (the system overlays the menu-bar/notch region in full-screen). Uses on-screen window
/// geometry from `CGWindowListCopyWindowInfo`, which reports bounds without Screen Recording
/// permission. Heuristic: a layer-0 window whose bounds cover the entire display.
final class FullScreenObserver {
    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var lastValue = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(check),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.check()
        }
        check()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }

    @objc private func check() {
        let value = isAnyWindowFullScreen()
        guard value != lastValue else { return }
        lastValue = value
        onChange(value)
    }

    private func isAnyWindowFullScreen() -> Bool {
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let tolerance: CGFloat = 3

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            // A window covering the full display (including the top/notch strip) ⇒ full-screen.
            if abs(bounds.minX - displayBounds.minX) <= tolerance,
               abs(bounds.minY - displayBounds.minY) <= tolerance,
               abs(bounds.width - displayBounds.width) <= tolerance,
               abs(bounds.height - displayBounds.height) <= tolerance {
                return true
            }
        }
        return false
    }
}
