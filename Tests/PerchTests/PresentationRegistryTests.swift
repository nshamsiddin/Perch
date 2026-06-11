import XCTest
@testable import Perch

final class PresentationRegistryTests: XCTestCase {
    private let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchWidth: 200,
        notchHeight: 32,
        hasNotch: true
    )

    func testVolumeHUDWinsOverPeek() {
        let state = IslandState()
        state.volumeHUD = VolumeHUD(level: 0.5, muted: false)
        state.currentActivity = Activity(symbol: "bell", text: "Hello")
        let layout = IslandLayout(geometry: geometry)
        let registry = PresentationRegistry(state: state, layout: layout)
        XCTAssertEqual(registry.presentation, .volumeHUD)
    }

    func testAgentLiveWhenEnabledAndActive() {
        let state = IslandState()
        state.agentsEnabled = true
        state.agentSessions = [
            AgentSession(
                id: "cursor:1", tool: .cursor, project: "Perch", cwd: "/tmp",
                state: .working, updatedAt: Date()
            )
        ]
        let layout = IslandLayout(geometry: geometry)
        let registry = PresentationRegistry(state: state, layout: layout)
        XCTAssertEqual(registry.presentation, .agentLive)
    }

    func testNowPlayingExpandHoverUsesNotchCenterOnly() {
        let state = IslandState()
        state.mediaEnabled = true
        state.nowPlaying = NowPlaying(
            title: "Song", artist: "Artist", album: "Album",
            isPlaying: true, source: "Spotify", bundleIdentifier: nil
        )
        let layout = IslandLayout(geometry: geometry)
        let registry = PresentationRegistry(state: state, layout: layout)
        XCTAssertEqual(registry.presentation, .nowPlayingCompact)

        let full = layout.hoverHotZone(width: layout.compactWidth)
        let expand = registry.collapsedExpandHoverZone(notchWidth: geometry.notchWidth)
        XCTAssertLessThan(expand.width, full.width)
    }
}
