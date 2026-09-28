import SwiftUI
import Combine

// MARK: - Share Background Style

enum ShareBackgroundStyle: String, CaseIterable, Identifiable {
    case blurredCover
    case solidColor
    case gradient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blurredCover: return L("share.bg_blurred")
        case .solidColor: return L("share.bg_solid")
        case .gradient: return L("share.bg_gradient")
        }
    }

    var iconName: String {
        switch self {
        case .blurredCover: return "photo.fill"
        case .solidColor: return "square.fill"
        case .gradient: return "paintbrush.fill"
        }
    }
}

// MARK: - Share Customization

class ShareCustomization: ObservableObject {
    // Vinyl
    @Published var vinylColorHex: String = "#1A1A1A" {
        didSet { overridesVinyl = true }
    }
    @Published var isTranslucent: Bool = false {
        didSet { overridesVinyl = true }
    }
    @Published private(set) var overridesVinyl = false
    @Published private(set) var overridesTextColor = false
    @Published private(set) var overridesFontDesign = false
    @Published private(set) var overridesFontWeight = false

    // Background
    @Published var backgroundStyle: ShareBackgroundStyle = .blurredCover
    @Published var backgroundColorHex: String = "#1C1C1E"
    @Published var gradientStartHex: String = "#2C3E50"
    @Published var gradientEndHex: String = "#000000"

    // Cover
    @Published var customCoverImage: UIImage? = nil

    // Text
    @Published var textColorHex: String = "#FFFFFF" {
        didSet { overridesTextColor = true }
    }
    @Published var titleFontSize: CGFloat = 18
    @Published var fontDesign: ShareFontDesign = .standard {
        didSet { overridesFontDesign = true }
    }
    @Published var fontWeight: ShareFontWeight = .bold {
        didSet { overridesFontWeight = true }
    }

    // Lyrics
    /// Total visible lyric blocks, including the current line. Radial cards
    /// distribute these around the current line; ripple cards use past lines.
    @Published var lyricsLineCount: Int = 3

    // Preset vinyl colors for quick selection
    static let presetVinylColors: [(name: String, hex: String)] = [
        ("Black", "#1A1A1A"),
        ("Red", "#C0392B"),
        ("Blue", "#2980B9"),
        ("Green", "#27AE60"),
        ("White", "#ECF0F1"),
        ("Orange", "#E67E22"),
        ("Purple", "#8E44AD"),
        ("Gold", "#D4AC0D"),
    ]

    // Computed helpers
    var vinylColor: Color {
        Color(hex: vinylColorHex) ?? Color(white: 0.1)
    }

    var effectiveCoverImage: UIImage? {
        customCoverImage
    }

    var textColor: Color {
        Color(hex: textColorHex) ?? .white
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex) ?? Color(white: 0.11)
    }

    var gradientStart: Color {
        Color(hex: gradientStartHex) ?? Color(red: 0.17, green: 0.24, blue: 0.31)
    }

    var gradientEnd: Color {
        Color(hex: gradientEndHex) ?? .black
    }

    /// Scale factor for card dimensions based on font size (base = 18pt)
    var cardScale: CGFloat {
        max(1.0, titleFontSize / 18.0)
    }

    var titleFont: Font {
        fontDesign.font(size: titleFontSize, weight: fontWeight.weight)
    }

    var subtitleFont: Font {
        fontDesign.font(size: max(11, titleFontSize - 4), weight: .medium)
    }

    var captionFont: Font {
        fontDesign.font(size: max(10, titleFontSize - 6), weight: .regular)
    }

    /// Whether any setting differs from defaults
    var hasChanges: Bool {
        overridesVinyl || overridesTextColor || overridesFontDesign || overridesFontWeight ||
        vinylColorHex != "#1A1A1A" ||
        isTranslucent != false ||
        backgroundStyle != .blurredCover ||
        backgroundColorHex != "#1C1C1E" ||
        gradientStartHex != "#2C3E50" ||
        gradientEndHex != "#000000" ||
        customCoverImage != nil ||
        textColorHex != "#FFFFFF" ||
        titleFontSize != 18 ||
        fontDesign != .standard ||
        fontWeight != .bold ||
        lyricsLineCount != 3
    }

    func reset() {
        vinylColorHex = "#1A1A1A"
        isTranslucent = false
        backgroundStyle = .blurredCover
        backgroundColorHex = "#1C1C1E"
        gradientStartHex = "#2C3E50"
        gradientEndHex = "#000000"
        customCoverImage = nil
        textColorHex = "#FFFFFF"
        titleFontSize = 18
        fontDesign = .standard
        fontWeight = .bold
        lyricsLineCount = 3
        overridesVinyl = false
        overridesTextColor = false
        overridesFontDesign = false
        overridesFontWeight = false
    }
}
