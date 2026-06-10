import SwiftUI

/// Adaptive color palette for the expanded panel, derived from the system appearance.
/// SwiftUI's `@Environment(\.colorScheme)` tracks `NSApp.effectiveAppearance` (which follows the
/// system Light/Dark setting), so reading it makes the panel switch automatically and live.
///
/// The collapsed pill and activity peek are intentionally NOT themed — they stay dark to blend
/// with the physically-black notch regardless of appearance.
struct IslandTheme {
    let scheme: ColorScheme

    var isLight: Bool { scheme == .light }

    /// Expanded panel background.
    var panelBackground: Color {
        isLight ? Color(white: 0.97) : .black
    }

    var panelStroke: Color {
        isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.06)
    }

    var shadowOpacity: Double {
        isLight ? 0.18 : 0.35
    }

    var primaryText: Color {
        isLight ? Color.black.opacity(0.9) : .white
    }

    var secondaryText: Color {
        isLight ? Color.black.opacity(0.5) : Color.white.opacity(0.65)
    }

    var tertiaryText: Color {
        isLight ? Color.black.opacity(0.35) : Color.white.opacity(0.4)
    }

    /// Fill behind transport buttons / the album-art tile.
    var controlFill: Color {
        isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.12)
    }

    var tileFill: Color {
        isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)
    }

    var controlIcon: Color {
        isLight ? Color.black.opacity(0.85) : .white
    }

    /// Battery tint when not charging / not low.
    var neutralTint: Color {
        isLight ? Color.black.opacity(0.7) : Color.white.opacity(0.85)
    }
}
