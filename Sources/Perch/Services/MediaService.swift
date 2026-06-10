import AppKit

/// Surfaces now-playing info and transport controls. Uses mediaremote-adapter when available
/// (universal), with AppleScript fallback for Music & Spotify.
final class MediaService {
    private let state: IslandState
    private let activity: ActivityCenter
    private let adapter = MediaRemoteAdapterClient()

    static let musicBundleID = "com.apple.Music"
    static let spotifyBundleID = "com.spotify.client"

    private let musicBundleID = MediaService.musicBundleID
    private let spotifyBundleID = MediaService.spotifyBundleID

    private let queue = DispatchQueue(label: "perch.media.applescript")
    private var fallbackTimer: Timer?
    private var lastTrackKey: String = ""
    private var lastArtworkKey: String = ""
    private var usingAdapter = false

    init(state: IslandState, activity: ActivityCenter) {
        self.state = state
        self.activity = activity
    }

    func start() {
        guard state.mediaEnabled, state.mediaSourceMode != .off else { return }
        state.mediaRemoteAvailable = adapter.probe()

        if state.mediaSourceMode == .universal, state.mediaRemoteAvailable {
            usingAdapter = true
            adapter.onUpdate = { [weak self] snapshot in
                self?.applyAdapter(snapshot)
            }
            adapter.startStreaming()
            return
        }

        usingAdapter = false
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(playerChanged),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(playerChanged),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        usingAdapter = false
        adapter.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func playerChanged() {
        refresh()
    }

    private func applyAdapter(_ snapshot: MediaRemoteAdapterClient.Snapshot) {
        let source = snapshot.bundleIdentifier.flatMap { Self.bundleDisplayName($0) } ?? "Now Playing"
        let np = NowPlaying(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            isPlaying: snapshot.isPlaying,
            source: source,
            bundleIdentifier: snapshot.bundleIdentifier
        )
        apply(np, artworkData: snapshot.artworkData)
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let running = self.runningPlayerBundleIDs()
            var result: NowPlaying = .empty

            if running.contains(self.spotifyBundleID), let np = self.querySpotify() {
                result = np
            }
            if running.contains(self.musicBundleID), let np = self.queryMusic() {
                if !result.hasContent || (np.isPlaying && !result.isPlaying) {
                    result = np
                }
            }

            DispatchQueue.main.async { self.apply(result) }
        }
    }

    private func apply(_ np: NowPlaying, artworkData: Data? = nil) {
        let key = "\(np.source)|\(np.title)|\(np.artist)"
        if np.hasContent, np.isPlaying, key != lastTrackKey {
            activity.show(symbol: "music.note", text: "\(np.title) — \(np.artist)")
        }
        if np.hasContent { lastTrackKey = key }
        state.nowPlaying = np

        if !np.hasContent {
            lastArtworkKey = ""
            state.artwork = nil
        } else if key != lastArtworkKey {
            lastArtworkKey = key
            if let artworkData, let image = NSImage(data: artworkData) {
                state.artwork = image
            } else {
                fetchArtwork(for: np, key: key)
            }
        }
    }

    private func fetchArtwork(for np: NowPlaying, key: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let image: NSImage?
            switch np.source {
            case "Spotify": image = self.fetchSpotifyArtwork()
            case "Music":   image = self.fetchMusicArtwork()
            default:        image = nil
            }
            DispatchQueue.main.async {
                guard self.lastArtworkKey == key else { return }
                self.state.artwork = image
            }
        }
    }

    private func fetchMusicArtwork() -> NSImage? {
        let source = "tell application \"Music\" to get data of artwork 1 of current track"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return nil }
        let data = descriptor.data
        guard !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    private func fetchSpotifyArtwork() -> NSImage? {
        let script = """
        tell application "Spotify"
            if it is running then
                return artwork url of current track
            end if
        end tell
        """
        guard let urlString = run(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              urlString.hasPrefix("https://"),
              let url = URL(string: urlString) else { return nil }

        var imageData: Data?
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                imageData = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        guard let data = imageData, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    func playPause() {
        if usingAdapter { adapter.sendCommand("playpause"); return }
        sendCommand("playpause")
    }

    func next() {
        if usingAdapter { adapter.sendCommand("next"); return }
        sendCommand("next track")
    }

    func previous() {
        if usingAdapter { adapter.sendCommand("previous"); return }
        sendCommand("previous track")
    }

    func launchSpotify() {
        activate(bundleID: spotifyBundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    func openCurrentSource() {
        if let bundleID = state.nowPlaying.bundleIdentifier {
            activate(bundleID: bundleID)
            return
        }
        switch state.nowPlaying.source {
        case "Spotify": activate(bundleID: spotifyBundleID)
        case "Music":   activate(bundleID: musicBundleID)
        default:        launchSpotify()
        }
    }

    private func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private func sendCommand(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let source = self.state.nowPlaying.source
            let running = self.runningPlayerBundleIDs()
            let target: String
            if source == "Spotify" || (source.isEmpty && running.contains(self.spotifyBundleID)) {
                target = "Spotify"
            } else if source == "Music" || running.contains(self.musicBundleID) {
                target = "Music"
            } else if running.contains(self.spotifyBundleID) {
                target = "Spotify"
            } else {
                return
            }
            _ = self.run("tell application \"\(target)\" to \(command)")
            self.refresh()
        }
    }

    private func runningPlayerBundleIDs() -> Set<String> {
        let ids = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        return Set(ids).intersection([musicBundleID, spotifyBundleID])
    }

    private func querySpotify() -> NowPlaying? {
        let script = """
        tell application "Spotify"
            if it is running then
                set playerState to (player state as text)
                set trackName to (name of current track)
                set artistName to (artist of current track)
                set albumName to (album of current track)
                return playerState & "\\n" & trackName & "\\n" & artistName & "\\n" & albumName
            end if
        end tell
        """
        guard let raw = run(script) else { return nil }
        return Self.parse(raw, source: "Spotify")
    }

    private func queryMusic() -> NowPlaying? {
        let script = """
        tell application "Music"
            if it is running then
                set playerState to (player state as text)
                if playerState is "stopped" then return "stopped"
                set trackName to (name of current track)
                set artistName to (artist of current track)
                set albumName to (album of current track)
                return playerState & "\\n" & trackName & "\\n" & artistName & "\\n" & albumName
            end if
        end tell
        """
        guard let raw = run(script) else { return nil }
        return Self.parse(raw, source: "Music")
    }

    static func parse(_ raw: String, source: String) -> NowPlaying? {
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 4 else { return nil }
        let stateString = parts[0].lowercased()
        return NowPlaying(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: stateString.contains("playing"),
            source: source,
            bundleIdentifier: nil
        )
    }

    static func parseAdapterJSON(_ line: String) -> NowPlaying? {
        guard let snapshot = MediaRemoteAdapterClient.parse(line: line) else { return nil }
        let source = snapshot.bundleIdentifier.flatMap { bundleDisplayName($0) } ?? "Now Playing"
        return NowPlaying(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            isPlaying: snapshot.isPlaying,
            source: source,
            bundleIdentifier: snapshot.bundleIdentifier
        )
    }

    private static func bundleDisplayName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID.split(separator: ".").last.map(String.init)
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}
