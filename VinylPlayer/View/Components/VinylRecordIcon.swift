import SwiftUI

/// Reusable vinyl record icon that adapts to light/dark mode.
/// In dark mode, colors are inverted so the icon remains visible.
struct VinylRecordIcon: View {
    let size: CGFloat
    var opacity: Double = 0.3

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("vinyl_record")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .opacity(opacity)
            .colorInvert(colorScheme == .dark)
    }
}

// MARK: - Conditional Color Invert

private extension View {
    @ViewBuilder
    func colorInvert(_ active: Bool) -> some View {
        if active {
            self.colorInvert()
        } else {
            self
        }
    }
}
