import SwiftUI
import UIKit

/// Visual themes for the app — user picks from the style picker.
/// All colors adapt automatically to light & dark mode via UIColor dynamic provider.
enum StyleTheme: String, Codable, CaseIterable, Identifiable {
    case skeuomorphic   // Realistic wood + metal
    case modern         // Minimal, clean
    case vintage        // 70s/80s retro warmth
    case neon           // Neon accent glow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skeuomorphic: return L("theme.classic")
        case .modern: return L("theme.modern")
        case .vintage: return L("theme.vintage")
        case .neon: return L("theme.neon")
        }
    }

    var description: String {
        switch self {
        case .skeuomorphic: return L("theme.classic_desc")
        case .modern: return L("theme.modern_desc")
        case .vintage: return L("theme.vintage_desc")
        case .neon: return L("theme.neon_desc")
        }
    }

    // MARK: - Adaptive Colors

    var backgroundColor: Color {
        adaptive(
            light: lightBackgroundHex,
            dark: darkBackgroundHex
        )
    }

    var surfaceColor: Color {
        adaptive(
            light: lightSurfaceHex,
            dark: darkSurfaceHex
        )
    }

    var accentColor: Color {
        adaptive(
            light: lightAccentHex,
            dark: darkAccentHex
        )
    }

    var secondaryAccent: Color {
        adaptive(
            light: lightSecondaryAccentHex,
            dark: darkSecondaryAccentHex
        )
    }

    var textPrimary: Color {
        adaptive(
            light: lightTextPrimaryHex,
            dark: darkTextPrimaryHex
        )
    }

    var textSecondary: Color {
        adaptive(
            light: lightTextSecondaryHex,
            dark: darkTextSecondaryHex
        )
    }

    var tonearmColor: Color {
        adaptive(
            light: lightTonearmHex,
            dark: darkTonearmHex
        )
    }

    // MARK: - Dark Mode Hex Values

    private var darkBackgroundHex: String {
        switch self {
        case .skeuomorphic: return "#3E2723"
        case .modern:       return "#0A0A0A"
        case .vintage:      return "#2C1810"
        case .neon:         return "#0D0D0D"
        }
    }

    private var darkSurfaceHex: String {
        switch self {
        case .skeuomorphic: return "#5D4037"
        case .modern:       return "#1A1A1A"
        case .vintage:      return "#4A3228"
        case .neon:         return "#1A1A2E"
        }
    }

    private var darkAccentHex: String {
        return "#5C95FF"
    }

    private var darkSecondaryAccentHex: String {
        switch self {
        case .skeuomorphic: return "#8D6E63"
        case .modern:       return "#888888"
        case .vintage:      return "#D4A574"
        case .neon:         return "#FF006E"
        }
    }

    private var darkTextPrimaryHex: String {
        switch self {
        case .skeuomorphic: return "#EFEBE9"
        case .modern:       return "#FFFFFF"
        case .vintage:      return "#F5E6D3"
        case .neon:         return "#FFFFFF"
        }
    }

    private var darkTextSecondaryHex: String {
        switch self {
        case .skeuomorphic: return "#BCAAA4"
        case .modern:       return "#888888"
        case .vintage:      return "#C4A882"
        case .neon:         return "#8888AA"
        }
    }

    private var darkTonearmHex: String {
        switch self {
        case .skeuomorphic: return "#C0C0C0"
        case .modern:       return "#CCCCCC"
        case .vintage:      return "#B8860B"
        case .neon:         return "#00FFCC"
        }
    }

    // MARK: - Light Mode Hex Values

    private var lightBackgroundHex: String {
        switch self {
        case .skeuomorphic: return "#F5EDE8"
        case .modern:       return "#F5F5F5"
        case .vintage:      return "#FDF3EB"
        case .neon:         return "#F0F0F8"
        }
    }

    private var lightSurfaceHex: String {
        switch self {
        case .skeuomorphic: return "#E8D8CC"
        case .modern:       return "#FFFFFF"
        case .vintage:      return "#F0DFD0"
        case .neon:         return "#E8E8F0"
        }
    }

    private var lightAccentHex: String {
        return "#5C95FF"
    }

    private var lightSecondaryAccentHex: String {
        switch self {
        case .skeuomorphic: return "#A1887F"
        case .modern:       return "#666666"
        case .vintage:      return "#C09878"
        case .neon:         return "#E84393"
        }
    }

    private var lightTextPrimaryHex: String {
        switch self {
        case .skeuomorphic: return "#3E2723"
        case .modern:       return "#1A1A1A"
        case .vintage:      return "#2C1810"
        case .neon:         return "#1A1A2E"
        }
    }

    private var lightTextSecondaryHex: String {
        switch self {
        case .skeuomorphic: return "#795548"
        case .modern:       return "#888888"
        case .vintage:      return "#8B6E5A"
        case .neon:         return "#666688"
        }
    }

    private var lightTonearmHex: String {
        switch self {
        case .skeuomorphic: return "#6D6D6D"
        case .modern:       return "#444444"
        case .vintage:      return "#8B6914"
        case .neon:         return "#00B894"
        }
    }

    // MARK: - Helper

    /// Creates a Color that automatically adapts to light/dark mode.
    private func adaptive(light lightHex: String, dark darkHex: String) -> Color {
        let lightUI = UIColor(Color(hex: lightHex) ?? .gray)
        let darkUI = UIColor(Color(hex: darkHex) ?? .gray)

        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? darkUI : lightUI
        })
    }
}
