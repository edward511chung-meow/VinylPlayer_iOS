import SwiftUI

struct TimedWordAttribute: TextAttribute { let index: Int }

// MARK: - Karaoke Text Renderer

/// TextRenderer that creates an Apple Music-style karaoke fill effect.
/// Uses actual `Text.Layout` line boundaries for pixel-perfect fill —
/// no line height estimation needed.
struct KaraokeRenderer: TextRenderer, Animatable {
    var fillProgress: Double
    var markerFillProgress: Double
    var showsHandwrittenHighlight = false
    var markerStyleSeed = 0
    var words: [SyncedLyricWord] = []
    var currentMs: Int = 0
    var fontSize: CGFloat = 26
    var displayScale: CGFloat = 3
    var reduceMotion: Bool = false
    private let unfilledOpacity: Double = 0.35
    private let bandWidth: CGFloat = 16
    private let markerColor = Color(red: 1.0, green: 0.93, blue: 0.22)

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fillProgress, markerFillProgress) }
        set {
            fillProgress = newValue.first
            markerFillProgress = newValue.second
        }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let lines = Array(layout)
        guard !lines.isEmpty else { return }

        // Allocate the line's elapsed time by rendered width. This keeps the
        // marker moving at a consistent visual speed when a lyric wraps into
        // one long row and one short row.
        let widths = lines.map { max(1, Double($0.typographicBounds.width)) }
        let totalWidth = max(1, widths.reduce(0, +))
        func progresses(for progress: Double) -> [Double] {
            let filledWidth = min(1, max(0, progress)) * totalWidth
            var consumedWidth = 0.0
            return widths.map { width -> Double in
                defer { consumedWidth += width }
                return min(1, max(0, (filledWidth - consumedWidth) / width))
            }
        }
        let lineProgresses = progresses(for: fillProgress)
        let markerLineProgresses = progresses(for: markerFillProgress)

        if showsHandwrittenHighlight {
            for (index, line) in lines.enumerated() {
                let markerProgress = markerLineProgresses[index]
                guard markerProgress > 0 else { continue }
                let variation = markerStyleSeed &+ index
                let style = positiveRemainder(variation, modulus: 4)
                let bounds = line.typographicBounds
                let rect = CGRect(
                    x: bounds.origin.x - 7,
                    y: bounds.origin.y - bounds.ascent - 2,
                    width: bounds.width + 14,
                    height: bounds.ascent + bounds.descent + bounds.leading + 5
                )
                let minimumNibWidth = min(rect.width, rect.height * 0.42)
                let revealedMarkerWidth = max(
                    minimumNibWidth,
                    rect.width * CGFloat(markerProgress)
                )
                context.drawLayer { markerContext in
                    let horizontalPadding: CGFloat = 8
                    let clipRect = CGRect(
                        x: rect.minX - horizontalPadding,
                        y: rect.minY - 3,
                        // Padding stays outside the timed portion. Previously
                        // it consumed the first few percent of progress, so a
                        // newly started marker appeared to be missing.
                        width: horizontalPadding + revealedMarkerWidth,
                        height: rect.height + 6
                    )
                    markerContext.clip(to: Path(clipRect))
                    markerContext.fill(
                        markerPath(in: rect, variation: variation),
                        with: .color(markerColor.opacity([0.50, 0.56, 0.48, 0.53][style]))
                    )

                    let verticalInset = [0.14, 0.18, 0.11, 0.16][style]
                    let verticalOffset = [0.06, 0.02, 0.09, 0.05][style]
                    var secondPass = rect.insetBy(dx: style == 2 ? 0 : 1, dy: rect.height * verticalInset)
                    secondPass.origin.y += rect.height * verticalOffset
                    markerContext.fill(
                        markerPath(in: secondPass, variation: variation + 1),
                        with: .color(markerColor.opacity([0.13, 0.17, 0.11, 0.15][style]))
                    )
                }

                // A real felt-tip marker leaves a slightly darker, rounded
                // pool at the marker's current synced endpoint.
                var progressedRect = rect
                progressedRect.size.width = revealedMarkerWidth
                context.fill(
                    markerEndPoolPath(in: progressedRect, variation: variation),
                    with: .color(markerColor.opacity([0.17, 0.21, 0.15, 0.19][style]))
                )
            }
        }

        if !words.isEmpty {
            drawTimedWords(lines: lines, in: &context)
            return
        }

        for (idx, line) in lines.enumerated() {
            let b = line.typographicBounds
            let inLineProgress = lineProgresses[idx]

            if inLineProgress >= 1 {
                // Fully filled line — draw at full opacity
                context.draw(line, options: .disablesSubpixelQuantization)
            } else if inLineProgress <= 0 {
                // Unfilled line — draw at reduced opacity
                var ctx = context
                ctx.opacity = unfilledOpacity
                ctx.draw(line, options: .disablesSubpixelQuantization)
            } else {
                // Partially filled line — clip filled & unfilled portions
                let fillX = b.origin.x + b.width * inLineProgress
                let lineTop = b.origin.y - b.ascent - 2
                let lineH = b.ascent + b.descent + b.leading + 4

                // Filled portion with gradient edge
                context.drawLayer { ctx in
                    // Draw full line first
                    ctx.draw(line, options: .disablesSubpixelQuantization)

                    // Erase unfilled area using destinationOut
                    ctx.blendMode = .destinationOut

                    let gradStart = max(b.origin.x, fillX - bandWidth)
                    let gradEnd = fillX + bandWidth

                    // Gradient transition
                    let gradRect = CGRect(x: gradStart, y: lineTop, width: gradEnd - gradStart, height: lineH)
                    ctx.fill(Path(gradRect), with: .linearGradient(
                        Gradient(colors: [.clear, .white]),
                        startPoint: CGPoint(x: gradStart, y: 0),
                        endPoint: CGPoint(x: gradEnd, y: 0)
                    ))

                    // Hard erase after gradient
                    if gradEnd < b.origin.x + b.width + 8 {
                        let eraseRect = CGRect(x: gradEnd, y: lineTop, width: b.origin.x + b.width - gradEnd + 8, height: lineH)
                        ctx.fill(Path(eraseRect), with: .color(.white))
                    }
                }

                // Unfilled portion at reduced opacity
                context.drawLayer { ctx in
                    ctx.opacity = unfilledOpacity
                    let startX = max(b.origin.x, fillX - bandWidth)
                    let clipRect = CGRect(x: startX, y: lineTop, width: b.origin.x + b.width - startX + 8, height: lineH)
                    ctx.clip(to: Path(clipRect))
                    ctx.draw(line, options: .disablesSubpixelQuantization)
                }
            }
        }
    }

    /// Builds a separate imperfect marker stroke for each rendered text line,
    /// so wrapped lyrics do not turn into one large rectangular block.
    private func drawTimedWords(lines: [Text.Layout.Line], in context: inout GraphicsContext) {
        var widths: [Int: CGFloat] = [:]
        for line in lines { for run in line {
            if let index = run[TimedWordAttribute.self]?.index { widths[index, default: 0] += run.typographicBounds.width }
        } }
        var consumed: [Int: CGFloat] = [:]
        for line in lines { for run in line {
            guard let index = run[TimedWordAttribute.self]?.index, words.indices.contains(index) else {
                context.draw(run); continue
            }
            let word = words[index]
            let fraction = KaraokeFill.fillFraction(for: word, atMs: currentMs)
            let stops = KaraokeFill.stops(left: fraction - KaraokeFill.wordEdgeSoftenBand,
                                         right: fraction + KaraokeFill.wordEdgeSoftenBand)
            let width = max(1, widths[index, default: 1])
            let bounds = run.typographicBounds.rect
            let origin = bounds.minX - consumed[index, default: 0]
            consumed[index, default: 0] += bounds.width
            let p = min(1, max(0, Double(currentMs - word.startMs) / min(1000, Double(max(1, word.durationMs)))))
            let amplitude = (fontSize * 0.05 * displayScale).rounded() / max(1, displayScale)
            var drawing = context
            drawing.translateBy(x: 0, y: reduceMotion ? 0 : -sin(p * .pi / 2) * amplitude)
            drawing.drawLayer { layer in
                layer.draw(run, options: .disablesSubpixelQuantization)
                layer.blendMode = .destinationOut
                layer.fill(Path(bounds.insetBy(dx: -2, dy: -4)), with: .linearGradient(
                    Gradient(stops: stops.map { .init(color: .white.opacity((1 - $0.intensity) * (1 - unfilledOpacity)), location: $0.location) }),
                    startPoint: CGPoint(x: origin, y: 0), endPoint: CGPoint(x: origin + width, y: 0)))
            }
        } }
    }

    private func markerPath(in rect: CGRect, variation: Int) -> Path {
        let style = positiveRemainder(variation, modulus: 4)
        let wobble = [0.04, -0.03, 0.065, -0.05][style] * rect.height
        let leadingLift = [0.20, 0.16, 0.23, 0.18][style] * rect.height
        let trailingInset = [0.10, 0.04, 0.15, 0.07][style] * rect.height
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let height = rect.height
        let width = rect.width

        var path = Path()
        path.move(to: CGPoint(x: left + 1, y: top + leadingLift))
        path.addQuadCurve(
            to: CGPoint(x: left + width * 0.26, y: top + height * 0.12 + wobble),
            control: CGPoint(x: left + width * 0.09, y: top + height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: right - trailingInset, y: top + height * 0.16 - wobble),
            control: CGPoint(x: left + width * 0.70, y: top + height * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: right - height * 0.04, y: bottom - height * 0.20),
            control: CGPoint(x: right + height * 0.10, y: top + height * 0.52)
        )
        path.addQuadCurve(
            to: CGPoint(x: left + width * 0.20, y: bottom - height * 0.14 + wobble),
            control: CGPoint(x: left + width * 0.70, y: bottom - height * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: left + 1, y: top + height * 0.24),
            control: CGPoint(x: left - 2, y: bottom - height * 0.34)
        )
        path.closeSubpath()
        return path
    }

    private func markerEndPoolPath(in rect: CGRect, variation: Int) -> Path {
        let height = rect.height
        let style = positiveRemainder(variation, modulus: 4)
        let wobble = [0.025, -0.02, 0.04, -0.032][style] * height
        let poolLength = [0.52, 0.44, 0.60, 0.49][style] * height
        let startX = rect.maxX - poolLength
        // Keep the pooled ink inside the original stroke endpoint.
        let endX = rect.maxX - height * 0.04
        let top = rect.minY + height * 0.17 + wobble
        let bottom = rect.maxY - height * 0.18 - wobble

        var path = Path()
        path.move(to: CGPoint(x: startX, y: top))
        path.addQuadCurve(
            to: CGPoint(x: endX, y: rect.midY),
            control: CGPoint(x: rect.maxX, y: top + height * 0.02)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX, y: bottom),
            control: CGPoint(x: rect.maxX, y: bottom - height * 0.02)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX, y: top),
            control: CGPoint(x: startX - height * 0.08, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }

    private func positiveRemainder(_ value: Int, modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}

// MARK: - Karaoke Lyric Text View

/// Apple Music-style karaoke lyric text using TextRenderer for precise line-by-line fill.
struct KaraokeLyricText: View {
    let text: String
    let fillProgress: Double   // 0...1
    var markerFillProgress: Double = 1
    let fontSize: CGFloat
    let weight: Font.Weight
    let filledColor: Color
    let unfilledColor: Color
    let maxWidth: CGFloat
    var showsHandwrittenHighlight: Bool = false
    var fontOverride: Font? = nil
    var words: [SyncedLyricWord] = []
    var playbackAnchor: LyricPlaybackAnchor? = nil
    var nextLineStartMs: Int? = nil
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var markerStyleSeed: Int {
        text.unicodeScalars.reduce(17) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
    }

    var body: some View {
        if let playbackAnchor, !words.isEmpty, words.map(\.text).joined() == text {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playbackAnchor.isPlaying)) { timeline in
                renderedText(at: playbackAnchor.milliseconds(at: timeline.date))
            }
        } else {
            renderedText(at: nil)
        }
    }

    private func renderedText(at milliseconds: Int?) -> some View {
        let timed = milliseconds == nil ? [] : KaraokeFill.tailClamped(words, nextLineStartMs: nextLineStartMs)
        let content = timed.isEmpty ? Text(text) : timed.enumerated().reduce(Text("")) { result, item in
            Text("\(result)\(Text(item.element.text).customAttribute(TimedWordAttribute(index: item.offset)))")
        }
        return content
            .font(fontOverride ?? .system(size: fontSize, weight: weight, design: .rounded))
            .foregroundColor(filledColor)
            .textRenderer(
                KaraokeRenderer(
                    fillProgress: fillProgress,
                    markerFillProgress: markerFillProgress,
                    showsHandwrittenHighlight: showsHandwrittenHighlight,
                    markerStyleSeed: markerStyleSeed,
                    words: timed, currentMs: milliseconds ?? 0, fontSize: fontSize,
                    displayScale: displayScale, reduceMotion: reduceMotion
                )
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}
