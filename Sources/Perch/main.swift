import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: background agent, no Dock icon, no menu bar app switching.
app.setActivationPolicy(.accessory)
app.run()
