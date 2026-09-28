import Foundation
import SwiftUI
import Combine

/// Manages in-app language switching.
/// Stores the user's preferred language and provides a bundle for the selected `.lproj`.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Language codes matching .lproj folder names.
    enum AppLanguage: String, CaseIterable, Identifiable {
        case system = "system"
        case en = "en"
        case zhHant = "zh-Hant"
        case zhHans = "zh-Hans"
        case ja = "ja"
        case ko = "ko"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "System"
            case .en: return "English"
            case .zhHant: return "繁體中文"
            case .zhHans: return "简体中文"
            case .ja: return "日本語"
            case .ko: return "한국어"
            }
        }
    }

    /// The user's selected language. "system" means follow device language.
    @AppStorage("appLanguage") var selectedLanguage: String = "system" {
        didSet {
            updateBundle()
            objectWillChange.send()
        }
    }

    /// The bundle pointing to the correct .lproj for the selected language.
    private(set) var bundle: Bundle = .main

    private init() {
        updateBundle()
    }

    private func updateBundle() {
        if selectedLanguage == "system" {
            bundle = .main
            return
        }

        // Try to find the .lproj bundle for the selected language
        if let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            // Fallback to main bundle
            bundle = .main
        }
    }

    /// Localize a key using the current language bundle.
    func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    /// Localize a key with format arguments.
    func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String(format: format, arguments: args)
    }
}

// MARK: - Global Helper

/// Shorthand for `LocalizationManager.shared.string(key)`.
func L(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}

/// Shorthand for `LocalizationManager.shared.string(key, args...)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: LocalizationManager.shared.bundle, comment: "")
    return String(format: format, arguments: args)
}
