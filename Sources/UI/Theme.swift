import SwiftUI

/// Defines visual design tokens for Windows 11 Fluent and Windows Classic (SndVol) styles.
enum MixerTheme {
    // Windows 11 Accent Color
    static let win11Blue = Color(red: 0.0, green: 0.47, blue: 0.84)
    static let win11MutedRed = Color(red: 0.90, green: 0.25, blue: 0.20)

    // Backgrounds
    static func cardBackground(isClassic: Bool) -> Color {
        if isClassic {
            return Color(nsColor: .windowBackgroundColor).opacity(0.85)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.65)
        }
    }

    static func columnBorder(isClassic: Bool) -> Color {
        if isClassic {
            return Color.black.opacity(0.18)
        } else {
            return Color.white.opacity(0.12)
        }
    }

    // Fader Track
    static func trackColor(isClassic: Bool) -> Color {
        if isClassic {
            return Color.black.opacity(0.35)
        } else {
            return Color.primary.opacity(0.12)
        }
    }

    // Fader Active Fill
    static func activeFill(isClassic: Bool, isMuted: Bool) -> Color {
        if isMuted { return Color.secondary.opacity(0.5) }
        return isClassic ? Color.accentColor : win11Blue
    }
}

