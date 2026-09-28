import SwiftUI

/// An intentionally imperfect marker stroke, with gently uneven edges and a
/// second translucent pass to suggest ink building up on paper.
private struct HandwrittenHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height

        var path = Path()
        path.move(to: CGPoint(x: width * 0.01, y: height * 0.20))
        path.addQuadCurve(
            to: CGPoint(x: width * 0.24, y: height * 0.12),
            control: CGPoint(x: width * 0.08, y: height * 0.08)
        )
        path.addLine(to: CGPoint(x: width * 0.58, y: height * 0.10))
        path.addQuadCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.16),
            control: CGPoint(x: width * 0.82, y: height * 0.11)
        )
        path.addQuadCurve(
            to: CGPoint(x: width * 0.98, y: height * 0.80),
            control: CGPoint(x: width * 1.04, y: height * 0.50)
        )
        path.addQuadCurve(
            to: CGPoint(x: width * 0.66, y: height * 0.88),
            control: CGPoint(x: width * 0.84, y: height * 0.82)
        )
        path.addLine(to: CGPoint(x: width * 0.19, y: height * 0.86))
        path.addQuadCurve(
            to: CGPoint(x: width * 0.01, y: height * 0.24),
            control: CGPoint(x: -width * 0.015, y: height * 0.60)
        )
        path.closeSubpath()
        return path
    }
}

/// Slightly darker rounded deposit at the end of the marker stroke.
private struct HandwrittenHighlightEndPoolShape: Shape {
    func path(in rect: CGRect) -> Path {
        let height = rect.height
        let startX = rect.maxX - height * 0.52
        // Darken the existing end instead of extending the marker's length.
        let endX = rect.maxX - height * 0.04
        let top = rect.minY + height * 0.17
        let bottom = rect.maxY - height * 0.18

        var path = Path()
        path.move(to: CGPoint(x: startX, y: top))
        path.addQuadCurve(
            to: CGPoint(x: endX, y: rect.midY),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX, y: bottom),
            control: CGPoint(x: rect.maxX, y: bottom)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX, y: top),
            control: CGPoint(x: startX - height * 0.08, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

private struct HandwrittenHighlight: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HandwrittenHighlightShape()
                    .fill(color.opacity(0.52))

                HandwrittenHighlightShape()
                    .fill(color.opacity(0.14))
                    .scaleEffect(x: 1.01, y: 0.72)
                    .offset(y: proxy.size.height * 0.08)
                    .blendMode(.multiply)

                HandwrittenHighlightEndPoolShape()
                    .fill(color.opacity(0.18))
                    .blendMode(.multiply)
            }
            .rotationEffect(.degrees(-0.35))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Adds a yellow, hand-drawn marker stroke behind the receiving view.
    func handwrittenHighlight(
        isActive: Bool,
        color: Color = Color(red: 1.0, green: 0.93, blue: 0.22)
    ) -> some View {
        background {
            if isActive {
                HandwrittenHighlight(color: color)
                    .padding(.horizontal, -7)
                    .padding(.vertical, -1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .animation(.easeOut(duration: 0.20), value: isActive)
    }
}
