import AppKit
import Sparkle

/// Sparkle-backed auto-update. Without a release EdDSA public key in Info.plist, update checks
/// may fail verification — acceptable for local ad-hoc builds.
final class UpdateService: NSObject {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
}
