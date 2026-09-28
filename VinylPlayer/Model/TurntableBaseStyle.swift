import SwiftUI

/// Predefined turntable base/plinth styles.
enum TurntableBaseStyle: String, CaseIterable, Identifiable {
    case darkWalnut
    case lightOak
    case ebony
    case whiteMaple
    case brushedAluminum
    case blackMarble

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .darkWalnut:       return L("base.dark_walnut")
        case .lightOak:         return L("base.light_oak")
        case .ebony:            return L("base.ebony")
        case .whiteMaple:       return L("base.white_maple")
        case .brushedAluminum:  return L("base.brushed_aluminum")
        case .blackMarble:      return L("base.black_marble")
        }
    }

    var iconName: String {
        switch self {
        case .darkWalnut, .lightOak, .ebony, .whiteMaple:
            return "square.fill"
        case .brushedAluminum:
            return "rectangle.fill"
        case .blackMarble:
            return "diamond.fill"
        }
    }

    /// Whether this style should show wood grain overlay.
    var showsWoodGrain: Bool {
        switch self {
        case .darkWalnut, .lightOak, .ebony, .whiteMaple: return true
        case .brushedAluminum, .blackMarble: return false
        }
    }

    // MARK: - Gradient Colors

    /// Main body gradient colors (top-leading → bottom-trailing).
    var gradientColors: [Color] {
        switch self {
        case .darkWalnut:
            return [
                Color(red: 0.28, green: 0.18, blue: 0.12),
                Color(red: 0.22, green: 0.14, blue: 0.09),
                Color(red: 0.18, green: 0.11, blue: 0.07)
            ]
        case .lightOak:
            return [
                Color(red: 0.72, green: 0.58, blue: 0.42),
                Color(red: 0.62, green: 0.48, blue: 0.34),
                Color(red: 0.55, green: 0.42, blue: 0.28)
            ]
        case .ebony:
            return [
                Color(red: 0.12, green: 0.10, blue: 0.08),
                Color(red: 0.08, green: 0.06, blue: 0.05),
                Color(red: 0.05, green: 0.04, blue: 0.03)
            ]
        case .whiteMaple:
            return [
                Color(red: 0.88, green: 0.82, blue: 0.74),
                Color(red: 0.82, green: 0.76, blue: 0.68),
                Color(red: 0.76, green: 0.70, blue: 0.62)
            ]
        case .brushedAluminum:
            return [
                Color(red: 0.72, green: 0.74, blue: 0.76),
                Color(red: 0.58, green: 0.60, blue: 0.62),
                Color(red: 0.48, green: 0.50, blue: 0.52)
            ]
        case .blackMarble:
            return [
                Color(red: 0.14, green: 0.14, blue: 0.16),
                Color(red: 0.08, green: 0.08, blue: 0.10),
                Color(red: 0.04, green: 0.04, blue: 0.06)
            ]
        }
    }

    // MARK: - Edge Highlight

    var edgeHighlightOpacity: (top: Double, bottom: Double) {
        switch self {
        case .darkWalnut:       return (0.08, 0.01)
        case .lightOak:         return (0.15, 0.03)
        case .ebony:            return (0.06, 0.01)
        case .whiteMaple:       return (0.20, 0.05)
        case .brushedAluminum:  return (0.25, 0.05)
        case .blackMarble:      return (0.10, 0.02)
        }
    }

    // MARK: - Wood Grain Colors

    /// Light band color range for WoodGrainCanvas (red, green, blue ranges).
    var grainLightColorRange: (r: ClosedRange<Double>, g: ClosedRange<Double>, b: ClosedRange<Double>) {
        switch self {
        case .darkWalnut:
            return (0.22...0.28, 0.14...0.18, 0.07...0.11)
        case .lightOak:
            return (0.60...0.68, 0.46...0.54, 0.30...0.38)
        case .ebony:
            return (0.10...0.14, 0.08...0.12, 0.06...0.09)
        case .whiteMaple:
            return (0.78...0.85, 0.72...0.78, 0.64...0.70)
        default:
            return (0.22...0.28, 0.14...0.18, 0.07...0.11) // unused
        }
    }

    /// Dark band color range for WoodGrainCanvas.
    var grainDarkColorRange: (r: ClosedRange<Double>, g: ClosedRange<Double>, b: ClosedRange<Double>) {
        switch self {
        case .darkWalnut:
            return (0.04...0.08, 0.02...0.05, 0.01...0.03)
        case .lightOak:
            return (0.48...0.55, 0.36...0.42, 0.22...0.28)
        case .ebony:
            return (0.03...0.06, 0.02...0.04, 0.01...0.03)
        case .whiteMaple:
            return (0.68...0.74, 0.62...0.68, 0.54...0.60)
        default:
            return (0.04...0.08, 0.02...0.05, 0.01...0.03) // unused
        }
    }

    /// Knot color for WoodGrainCanvas.
    var grainKnotColor: Color {
        switch self {
        case .darkWalnut:   return Color(red: 0.20, green: 0.12, blue: 0.06)
        case .lightOak:     return Color(red: 0.52, green: 0.40, blue: 0.26)
        case .ebony:        return Color(red: 0.08, green: 0.06, blue: 0.04)
        case .whiteMaple:   return Color(red: 0.70, green: 0.64, blue: 0.56)
        default:            return Color(red: 0.20, green: 0.12, blue: 0.06) // unused
        }
    }

    // MARK: - Shadow

    var shadowOpacity: Double {
        switch self {
        case .whiteMaple, .lightOak: return 0.30
        default: return 0.45
        }
    }
}
