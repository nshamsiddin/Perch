import AppKit
import Combine

/// Visual mode of the island.
enum IslandMode: Equatable {
    case collapsed
    case expanded
}

/// Now-playing snapshot surfaced by `MediaService`.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var source: String // "Music" or "Spotify"

    static let empty = NowPlaying(title: "", artist: "", album: "", isPlaying: false, source: "")

    var hasContent: Bool { !title.isEmpty }
}

/// Battery / power snapshot surfaced by `BatteryService`.
struct BatteryStatus: Equatable {
    var percentage: Int          // 0...100, -1 when unknown
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool

    static let unknown = BatteryStatus(percentage: -1, isCharging: false, isPluggedIn: false, hasBattery: false)
}

/// A transient output-volume HUD shown flanking the notch when volume/mute changes.
struct VolumeHUD: Equatable {
    var level: Double   // 0.0...1.0 output scalar
    var muted: Bool
}

/// A transient live-activity peek.
struct Activity: Identifiable, Equatable {
    let id: UUID
    var symbol: String   // SF Symbol name
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), symbol: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.symbol = symbol
        self.text = text
        self.createdAt = createdAt
    }
}

/// Shared, observable application state. The single source of truth bound to the SwiftUI island.
final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .collapsed
    @Published var geometry: NotchGeometry = .fallback
    @Published var isHiddenForFullScreen: Bool = false

    @Published var nowPlaying: NowPlaying = .empty
    /// Album artwork for the current track. Kept out of `NowPlaying` so the struct can stay
    /// `Equatable` (NSImage isn't value-comparable) and so artwork can update independently.
    @Published var artwork: NSImage?
    @Published var battery: BatteryStatus = .unknown

    /// Most-recent live activity, shown as a transient peek next to the notch.
    @Published var currentActivity: Activity?

    /// Transient output-volume HUD; non-nil while the speaker/level HUD is visible.
    @Published var volumeHUD: VolumeHUD?

    func setMode(_ newMode: IslandMode) {
        guard mode != newMode else { return }
        mode = newMode
    }
}
