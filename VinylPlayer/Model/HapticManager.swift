import UIKit
import SwiftUI

/// Centralized haptic feedback with user-configurable intensity.
enum HapticIntensity: String, CaseIterable, Identifiable, Codable {
    case off = "off"
    case light = "light"
    case medium = "medium"
    case heavy = "heavy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:    return L("haptic.off")
        case .light:  return L("haptic.light")
        case .medium: return L("haptic.medium")
        case .heavy:  return L("haptic.heavy")
        }
    }

    var iconName: String {
        switch self {
        case .off:    return "iphone.slash"
        case .light:  return "iphone.radiowaves.left.and.right.circle"
        case .medium: return "iphone.radiowaves.left.and.right"
        case .heavy:  return "waveform.path"
        }
    }

    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self {
        case .off:    return nil
        case .light:  return .light
        case .medium: return .medium
        case .heavy:  return .heavy
        }
    }
}

final class HapticManager {
    static let shared = HapticManager()

    private var lightGenerator: UIImpactFeedbackGenerator?
    private var mediumGenerator: UIImpactFeedbackGenerator?
    private var heavyGenerator: UIImpactFeedbackGenerator?
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        lightGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    }

    /// Trigger an impact haptic at the given intensity.
    func impact(_ intensity: HapticIntensity) {
        guard let style = intensity.feedbackStyle else { return }
        switch style {
        case .light:  lightGenerator?.impactOccurred()
        case .medium: mediumGenerator?.impactOccurred()
        case .heavy:  heavyGenerator?.impactOccurred()
        default:      mediumGenerator?.impactOccurred()
        }
    }

    /// Trigger a selection tick (subtle, for scrolling through items).
    func selectionTick(_ intensity: HapticIntensity) {
        guard intensity != .off else { return }
        selectionGenerator.selectionChanged()
    }

    /// Trigger a notification haptic (success, warning, error).
    func notification(_ intensity: HapticIntensity, type: UINotificationFeedbackGenerator.FeedbackType) {
        guard intensity != .off else { return }
        notificationGenerator.notificationOccurred(type)
    }

    /// Prepare generators for lower latency.
    func prepare(_ intensity: HapticIntensity) {
        guard intensity != .off else { return }
        
        selectionGenerator.prepare()
        
        switch intensity.feedbackStyle {
        case .light:  lightGenerator?.prepare()
        case .medium: mediumGenerator?.prepare()
        case .heavy:  heavyGenerator?.prepare()
        default:      break
        }
    }
}
