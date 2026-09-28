import SwiftUI

// MARK: - Share Font Style

enum ShareFontDesign: String, CaseIterable, Identifiable {
    // System designs
    case standard
    case rounded
    case serif
    case monospaced
    // iOS built-in fonts
    case avenirNext
    case futura
    case georgia
    case didot
    case palatino

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return L("share.font_standard")
        case .rounded: return L("share.font_rounded")
        case .serif: return L("share.font_serif")
        case .monospaced: return L("share.font_mono")
        case .avenirNext: return "Avenir Next"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        case .didot: return "Didot"
        case .palatino: return "Palatino"
        }
    }

    /// System font design (nil for custom fonts)
    var design: Font.Design? {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        default: return nil
        }
    }

    /// Custom font family name (nil for system designs)
    var customFontName: String? {
        switch self {
        case .avenirNext: return "Avenir Next"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        case .didot: return "Didot"
        case .palatino: return "Palatino"
        default: return nil
        }
    }

    /// Build a Font at the given size and weight
    func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let name = customFontName {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: design ?? .default)
    }
}

enum ShareFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return L("share.weight_regular")
        case .medium: return L("share.weight_medium")
        case .semibold: return L("share.weight_semibold")
        case .bold: return L("share.weight_bold")
        case .heavy: return L("share.weight_heavy")
        }
    }

    var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

