import SwiftUI

/// A button style that provides a subtle scale + opacity press feedback,
/// following Apple's design principles for tactile responsiveness.
struct PressableButtonStyle: ButtonStyle {
    var scaleEffect: CGFloat = 0.92
    var pressedOpacity: CGFloat = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleEffect : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Default pressable style with scale 0.92 and opacity 0.7 on press.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }

    /// Pressable style with custom scale and opacity values.
    static func pressable(scale: CGFloat = 0.92, opacity: CGFloat = 0.7) -> PressableButtonStyle {
        PressableButtonStyle(scaleEffect: scale, pressedOpacity: opacity)
    }
}
