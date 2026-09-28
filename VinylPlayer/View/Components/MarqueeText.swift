import SwiftUI

/// A text view that scrolls horizontally when the content is wider than the container.
/// Shows static text if it fits; animates a looping scroll if it overflows.
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var foregroundColor: Color = .primary
    var speed: Double = 30 // points per second
    var delayBeforeScroll: Double = 1.5 // seconds before starting
    var spacing: CGFloat = 40 // gap between repeated text

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var overflows: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    /// Total distance for one full scroll cycle.
    private var scrollDistance: CGFloat {
        textWidth + spacing
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                if overflows {
                    // Two copies side by side for seamless loop
                    HStack(spacing: spacing) {
                        textView
                        textView
                    }
                    .offset(x: offset)
                } else {
                    // Fits — respect the caller's alignment, no animation.
                    textView
                        .frame(maxWidth: .infinity, alignment: alignment)
                }
            }
            .frame(width: w, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = w }
            .onChange(of: w) { _, newW in containerWidth = newW }
        }
        .frame(height: textHeight)
        .onChange(of: overflows) { _, shouldAnimate in
            if shouldAnimate {
                startScrolling()
            } else {
                stopScrolling()
            }
        }
        .onChange(of: text) { _, _ in
            // Reset when text changes
            stopScrolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if overflows { startScrolling() }
            }
        }
        .onAppear {
            if overflows { startScrolling() }
        }
    }

    private var textView: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { g in
                    Color.clear.onAppear { textWidth = g.size.width }
                }
            )
    }

    /// Approximate font size for height calculation.
    var fontSize: CGFloat = 17
    var alignment: Alignment = .center

    private var textHeight: CGFloat {
        let uiFont = UIFont.systemFont(ofSize: fontSize)
        return uiFont.lineHeight + 4
    }

    private func startScrolling() {
        guard !reduceMotion else { return }
        offset = 0
        animating = false

        DispatchQueue.main.asyncAfter(deadline: .now() + delayBeforeScroll) {
            guard overflows else { return }
            animating = true
            let duration = scrollDistance / speed
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -scrollDistance
            }
        }
    }

    private func stopScrolling() {
        animating = false
        withAnimation(.easeOut(duration: 0.3)) {
            offset = 0
        }
    }
}
