import AppKit
import Foundation

/// Reads system-wide now playing via the bundled mediaremote-adapter Perl helper.
final class MediaRemoteAdapterClient {
    struct Snapshot: Equatable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var bundleIdentifier: String?
        var artworkData: Data?
    }

    private var process: Process?
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "perch.mediaremote.adapter")
    var onUpdate: ((Snapshot) -> Void)?

    static func bundledResourcesURL() -> URL? {
        if let url = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl", subdirectory: "MediaRemoteAdapter") {
            return url.deletingLastPathComponent()
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter/mediaremote-adapter.pl"),
           FileManager.default.fileExists(atPath: url.path) {
            return url.deletingLastPathComponent()
        }
        return nil
    }

    func probe() -> Bool {
        guard let dir = Self.bundledResourcesURL() else { return false }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script.path, framework.path, "test"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    func startStreaming() {
        stop()
        guard let dir = Self.bundledResourcesURL() else { return }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script.path, framework.path, "stream"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return
        }
        process = proc
        let handle = pipe.fileHandleForReading
        readSource = DispatchSource.makeReadSource(fileDescriptor: handle.fileDescriptor, queue: queue)
        var buffer = Data()
        readSource?.setEventHandler { [weak self] in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(0...(newline))
                if let line = String(data: lineData, encoding: .utf8),
                   let snapshot = Self.parse(line: line) {
                    DispatchQueue.main.async { self?.onUpdate?(snapshot) }
                }
            }
        }
        readSource?.setCancelHandler { try? handle.close() }
        readSource?.resume()
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    func sendCommand(_ command: String) {
        guard let dir = Self.bundledResourcesURL() else { return }
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        queue.async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            proc.arguments = [script.path, framework.path, "command", command]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    static func parse(line: String) -> Snapshot? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let title = json["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        return Snapshot(
            title: title,
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            isPlaying: json["playing"] as? Bool ?? false,
            bundleIdentifier: json["bundleIdentifier"] as? String,
            artworkData: nil
        )
    }
}
