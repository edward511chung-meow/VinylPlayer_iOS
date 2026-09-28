import SwiftUI
import Combine

/// Available alternate app icons.
enum AppIcon: String, CaseIterable, Identifiable {
    // Base variants (different turntable base materials)
    case `default` = "AppIcon"
    case darkWalnut = "AppIconDarkWalnut"
    case whiteOak = "AppIconWhiteOak"
    case ebony = "AppIconEbony"

    // Colored vinyl variants (translucent, on walnut base)
    case orangeVinyl = "AppIconOrange"
    case blueVinyl = "AppIconBlue"
    case clearVinyl = "AppIconClear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return L("app_icon.default")
        case .darkWalnut: return L("app_icon.dark_walnut")
        case .whiteOak: return L("app_icon.white_oak")
        case .ebony: return L("app_icon.ebony")
        case .orangeVinyl: return L("app_icon.orange_vinyl")
        case .blueVinyl: return L("app_icon.blue_vinyl")
        case .clearVinyl: return L("app_icon.clear_vinyl")
        }
    }

    /// Image asset name for the picker grid preview.
    var previewImageName: String {
        switch self {
        case .default: return "AppIconPreviewV2"
        case .darkWalnut: return "AppIconDarkWalnutPreviewV2"
        case .whiteOak: return "AppIconWhiteOakPreviewV2"
        case .ebony: return "AppIconEbonyPreviewV2"
        case .orangeVinyl: return "AppIconOrangePreviewV2"
        case .blueVinyl: return "AppIconBluePreviewV2"
        case .clearVinyl: return "AppIconClearPreviewV2"
        }
    }

    /// The name passed to `setAlternateIconName`. `nil` = primary icon.
    var iconName: String? {
        self == .default ? nil : rawValue
    }
}

/// Manages alternate app icon selection.
final class AppIconManager: ObservableObject {
    @Published private(set) var currentIcon: AppIcon

    static let shared = AppIconManager()

    private init() {
        let current = UIApplication.shared.alternateIconName
        currentIcon = AppIcon.allCases.first { $0.iconName == current } ?? .default
    }

    func setIcon(_ icon: AppIcon) {
        guard icon != currentIcon else { return }
        UIApplication.shared.setAlternateIconName(icon.iconName) { [weak self] error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.currentIcon = icon
                }
            }
        }
    }
}
