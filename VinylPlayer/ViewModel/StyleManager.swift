import SwiftUI
import Combine

/// Manages the current visual theme, appearance mode, and haptic settings across the app.
final class StyleManager: ObservableObject {
    @Published var theme: StyleTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: AppConstants.StorageKeys.selectedStyleTheme)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: AppConstants.StorageKeys.appearanceMode)
        }
    }

    @Published var hapticIntensity: HapticIntensity {
        didSet {
            UserDefaults.standard.set(hapticIntensity.rawValue, forKey: AppConstants.StorageKeys.hapticIntensity)
        }
    }

    @Published var lyricsDisplayMode: LyricsDisplayMode {
        didSet {
            UserDefaults.standard.set(lyricsDisplayMode.rawValue, forKey: AppConstants.StorageKeys.lyricsDisplayMode)
        }
    }

    @Published var turntableBaseStyle: TurntableBaseStyle {
        didSet {
            UserDefaults.standard.set(turntableBaseStyle.rawValue, forKey: AppConstants.StorageKeys.turntableBaseStyle)
            WidgetDataManager.shared.updateBaseStyle(turntableBaseStyle)
        }
    }

    /// Returns the `ColorScheme` override, or nil to follow system.
    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.selectedStyleTheme),
           let theme = StyleTheme(rawValue: saved) {
            self.theme = theme
        } else {
            self.theme = .modern
        }

        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.appearanceMode),
           let mode = AppearanceMode(rawValue: saved) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.hapticIntensity),
           let intensity = HapticIntensity(rawValue: saved) {
            self.hapticIntensity = intensity
        } else {
            self.hapticIntensity = .medium
        }

        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.lyricsDisplayMode),
           let mode = LyricsDisplayMode(rawValue: saved) {
            self.lyricsDisplayMode = mode
        } else {
            self.lyricsDisplayMode = .radial
        }

        if let saved = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.turntableBaseStyle),
           let style = TurntableBaseStyle(rawValue: saved) {
            self.turntableBaseStyle = style
        } else {
            self.turntableBaseStyle = .darkWalnut
        }
    }
}

// MARK: - Lyrics Display Mode

enum LyricsDisplayMode: String, CaseIterable, Identifiable {
    case radial
    case ripple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .radial: return L("lyrics.radial")
        case .ripple: return L("lyrics.ripple")
        }
    }

    var description: String {
        switch self {
        case .radial: return L("lyrics.radial_desc")
        case .ripple: return L("lyrics.ripple_desc")
        }
    }

    var iconName: String {
        switch self {
        case .radial: return "rays"
        case .ripple: return "circle.circle"
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("appearance.system")
        case .light: return L("appearance.light")
        case .dark: return L("appearance.dark")
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
