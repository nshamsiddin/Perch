import Foundation
import SwiftUI
import CoreAudio
import AudioToolbox

/// Watches the system default output device for volume / mute changes via CoreAudio and
/// surfaces a transient HUD in the island. No permissions are required for CoreAudio
/// property listeners.
///
/// Listener design:
///   • System object (`kAudioObjectSystemObject`) is observed for
///     `kAudioHardwarePropertyDefaultOutputDevice`; when the default output device changes
///     (e.g. plugging in headphones) we detach from the old device and re-attach to the new one.
///   • The current default output device is observed for
///     `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (the virtual main volume that the
///     menu-bar / keyboard maps to) and `kAudioDevicePropertyMute`, both on the output scope and
///     main element.
/// All listener blocks run on a private serial queue; UI mutations hop to the main thread.
final class VolumeService {
    private let state: IslandState
    private let queue = DispatchQueue(label: "com.islet.volume")

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    /// Last observed values, used to de-dupe redundant callbacks.
    private var lastLevel: Double = 0
    private var lastMuted: Bool = false
    /// Only fire the HUD once we've established a baseline (so the initial read at startup
    /// and re-reads after a device switch don't pop the HUD — only real user changes do).
    private var armed = false

    private var dismissWorkItem: DispatchWorkItem?
    private let visibleDuration: TimeInterval = 1.3

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init(state: IslandState) {
        self.state = state
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.registerDefaultDeviceListener()
            self.attachToCurrentDefaultDevice()
            // Arm only after the baseline read so startup doesn't trigger a HUD.
            self.armed = true
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.armed = false
            self.detachFromCurrentDevice()
            if let listener = self.defaultDeviceListener {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &self.defaultDeviceAddress, self.queue, listener
                )
            }
            self.defaultDeviceListener = nil
        }
    }

    // MARK: - Listener registration (private serial queue)

    private func registerDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // Default output device changed: rebind listeners to the new device.
            self.detachFromCurrentDevice()
            self.attachToCurrentDefaultDevice()
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress, queue, block
        )
    }

    private func attachToCurrentDefaultDevice() {
        let device = currentDefaultOutputDevice()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        deviceID = device

        // Baseline read (does not fire the HUD).
        lastLevel = readVolume(device)
        lastMuted = readMute(device)

        let changeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleChange()
        }
        volumeListener = changeBlock
        muteListener = changeBlock

        if AudioObjectHasProperty(device, &volumeAddress) {
            AudioObjectAddPropertyListenerBlock(device, &volumeAddress, queue, changeBlock)
        }
        if AudioObjectHasProperty(device, &muteAddress) {
            AudioObjectAddPropertyListenerBlock(device, &muteAddress, queue, changeBlock)
        }
    }

    private func detachFromCurrentDevice() {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return }
        if let listener = volumeListener, AudioObjectHasProperty(deviceID, &volumeAddress) {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, queue, listener)
        }
        if let listener = muteListener, AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, queue, listener)
        }
        volumeListener = nil
        muteListener = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Change handling

    private func handleChange() {
        let device = deviceID
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }

        let level = readVolume(device)
        let muted = readMute(device)

        // De-dupe: CoreAudio can deliver multiple callbacks per logical change.
        if abs(level - lastLevel) < 0.0005 && muted == lastMuted { return }
        lastLevel = level
        lastMuted = muted

        guard armed else { return }

        let hud = VolumeHUD(level: level, muted: muted)
        DispatchQueue.main.async { [weak self] in
            self?.showHUD(hud)
        }
        // Best-effort: hide macOS's native volume bezel so only Islet's HUD shows.
        hideNativeBezel()
    }

    // MARK: - HUD presentation (main thread)

    private func showHUD(_ hud: VolumeHUD) {
        dismissWorkItem?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            state.volumeHUD = hud
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                self.state.volumeHUD = nil
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
    }

    // MARK: - CoreAudio reads

    private func currentDefaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress, 0, nil, &size, &device
        )
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    private func readVolume(_ device: AudioObjectID) -> Double {
        guard AudioObjectHasProperty(device, &volumeAddress) else { return 0 }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value)
        guard status == noErr else { return 0 }
        return Double(min(1, max(0, value)))
    }

    private func readMute(_ device: AudioObjectID) -> Bool {
        guard AudioObjectHasProperty(device, &muteAddress) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value)
        guard status == noErr else { return false }
        return value != 0
    }

    // MARK: - Native bezel suppression

    /// Best-effort kill of OSDUIHelper (which draws the native volume bezel). Fixed executable
    /// path and fixed arguments — no shell, no interpolated input. OSDUIHelper respawns on the
    /// next system OSD, so killing it per-change is safe; failures (e.g. not running) are ignored.
    private func hideNativeBezel() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["OSDUIHelper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            // Best-effort only; ignore (e.g. OSDUIHelper not currently running).
        }
    }
}
