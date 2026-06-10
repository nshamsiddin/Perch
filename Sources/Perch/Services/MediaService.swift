import AppKit

/// Surfaces now-playing info and transport controls for Music & Spotify via AppleScript.
/// Updates are driven by each app's distributed notification (instant, cheap), with a slow
/// timer as a fallback. MediaRemote is intentionally not used: it returns nil for unentitled
/// apps on macOS 15.4+. Artwork / arbitrary-app support is a documented v1.5 upgrade.
final class MediaService {
    private let state: IslandState
    private let activity: ActivityCenter

    static let musicBundleID = "com.apple.Music"
    static let spotifyBundleID = "com.spotify.client"

    private let musicBundleID = MediaService.musicBundleID
    private let spotifyBundleID = MediaService.spotifyBundleID

    private let queue = DispatchQueue(label: "perch.media.applescript")
    private var fallbackTimer: Timer?
    private var lastTrackKey: String = ""
    /// Separate key so artwork is fetched only once per track (the 5s refresh fires often).
    private var lastArtworkKey: String = ""

    init(state: IslandState, activity: ActivityCenter) {
        self.state = state
        self.activity = activity
    }

    func start() {
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
        DistributedNotificationCenter.default().removeObserver(self)
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func playerChanged() {
        refresh()
    }

    // MARK: - Query

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let running = self.runningPlayerBundleIDs()
            var result: NowPlaying = .empty

            // Prefer a source that is actively playing; otherwise fall back to any paused track.
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

    private func apply(_ np: NowPlaying) {
        let key = "\(np.source)|\(np.title)|\(np.artist)"
        if np.hasContent, np.isPlaying, key != lastTrackKey {
            activity.show(symbol: "music.note", text: "\(np.title) — \(np.artist)")
        }
        if np.hasContent { lastTrackKey = key }
        state.nowPlaying = np

        // Artwork: clear when there's nothing playing; otherwise (re)fetch only on track change.
        if !np.hasContent {
            lastArtworkKey = ""
            state.artwork = nil
        } else if key != lastArtworkKey {
            lastArtworkKey = key
            fetchArtwork(for: np, key: key)
        }
    }

    // MARK: - Artwork

    /// Fetches artwork off the main thread and applies it only if the track hasn't changed since.
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
                // Drop stale results from a track that has since changed.
                guard self.lastArtworkKey == key else { return }
                self.state.artwork = image
            }
        }
    }

    /// Music returns the raw image bytes directly via the AppleScript result descriptor.
    private func fetchMusicArtwork() -> NSImage? {
        let source = "tell application \"Music\" to get data of artwork 1 of current track"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return nil } // no track / no artwork / not authorized yet
        let data = descriptor.data
        guard !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    /// Spotify returns an https artwork URL we download ourselves.
    private func fetchSpotifyArtwork() -> NSImage? {
        let script = """
        tell application "Spotify"
            if it is running then
                return artwork url of current track
            end if
        end tell
        """
        guard let urlString = run(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              urlString.hasPrefix("https://"),            // HTTPS only — never fetch over http
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
        // We're already on a background queue, so blocking here is safe and keeps fetch ordered.
        _ = semaphore.wait(timeout: .now() + 10)

        guard let data = imageData, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Controls

    func playPause() { sendCommand("playpause") }
    func next() { sendCommand("next track") }
    func previous() { sendCommand("previous track") }

    /// Launches (or activates) Spotify, then refreshes once it's had a moment to come up — used by
    /// the "nothing playing" affordance so the user can start a source straight from the island.
    func launchSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleID)
        else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.refresh() }
        }
    }

    /// Brings the app that owns the current track to the front — tapping the now-playing mini
    /// player jumps to Spotify or Music. Falls back to launching Spotify when nothing is playing.
    func openCurrentSource() {
        switch state.nowPlaying.source {
        case "Spotify": activate(bundleID: spotifyBundleID)
        case "Music":   activate(bundleID: musicBundleID)
        default:        launchSpotify()
        }
    }

    /// Activates (or launches) the app for a bundle id, bringing its window to the front.
    private func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
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

    // MARK: - AppleScript helpers

    private func runningPlayerBundleIDs() -> Set<String> {
        let ids = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        return Set(ids).intersection([musicBundleID, spotifyBundleID])
    }

    // NOTE: use descriptive variable names. Short names like `st`, `t`, `a`, `al` collide with
    // AppleScript tokens and make the script fail to compile (returning nil silently).
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
            source: source
        )
    }

    /// Runs an AppleScript and returns its string result, or nil on error. Errors are expected
    /// when the target app isn't authorized yet (Automation prompt) or has no current track.
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}
