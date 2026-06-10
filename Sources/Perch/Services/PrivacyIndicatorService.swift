import AVFoundation
import AppKit
import CoreAudio

/// Detects camera, microphone, and screen-capture activity for the privacy ear indicator.
final class PrivacyIndicatorService {
    private let state: IslandState
    private var timer: Timer?

    init(state: IslandState) {
        self.state = state
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state.privacyStatus = PrivacyStatus()
    }

    private func sample() {
        var status = PrivacyStatus()
        status.cameraActive = cameraInUse()
        status.micActive = microphoneInUse()
        status.screenCaptureActive = screenCaptureInUse()
        if status.isActive {
            status.activeAppName = frontmostAppName()
        }
        if status != state.privacyStatus {
            state.privacyStatus = status
        }
    }

    private func cameraInUse() -> Bool {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.builtInWideAngleCamera, .external]
        } else {
            types = [.builtInWideAngleCamera]
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.contains { $0.isConnected && $0.isInUseByAnotherApplication }
    }

    private func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr else { return false }

        var running: UInt32 = 0
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private func screenCaptureInUse() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return windows.contains { info in
            let name = (info[kCGWindowName as String] as? String ?? "").lowercased()
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            return name.contains("screen") && name.contains("recording")
                || owner.contains("screensharing")
        }
    }

    private func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
