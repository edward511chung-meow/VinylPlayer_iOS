import SwiftUI

/// Water-ripple lyrics: the current line stays at the focal arc while played
/// lines disperse outward in stable pseudo-random directions.
struct RippleLyricsLayer: View, Equatable {
    var timedLines: [LyricLine] = []
    var playbackAnchor: LyricPlaybackAnchor? = nil
    let lines: [String]
    let currentIndex: Int
    let intraLineProgress: Double
    var markerIntraLineProgress: Double = 1
    var appearance = LyricTextAppearance()
    let vinylCenterX: CGFloat
    let vinylCenterY: CGFloat
    let vinylRadius: CGFloat
    let screenWidth: CGFloat
    var screenHeight: CGFloat? = nil

    static func == (lhs: RippleLyricsLayer, rhs: RippleLyricsLayer) -> Bool {
        lhs.timedLines == rhs.timedLines && lhs.playbackAnchor == rhs.playbackAnchor
            && lhs.lines == rhs.lines
            && lhs.currentIndex == rhs.currentIndex
            && lhs.intraLineProgress == rhs.intraLineProgress
            && lhs.markerIntraLineProgress == rhs.markerIntraLineProgress
            && lhs.appearance == rhs.appearance
            && lhs.vinylCenterX == rhs.vinylCenterX
            && lhs.vinylCenterY == rhs.vinylCenterY
            && lhs.vinylRadius == rhs.vinylRadius
            && lhs.screenWidth == rhs.screenWidth
            && lhs.screenHeight == rhs.screenHeight
    }

    private let maxVisibleLines = 12

    /// The arc starts at this angle (0° = right / 3 o'clock).
    /// 30° = slightly above horizontal-right, avoids left-side clipping.
    private let arcStartAngle: Double = 15

    /// A fixed, compact low-discrepancy order. Each lyric keeps the same slot
    /// for its whole lifetime, so advancing playback never reshuffles lyrics
    /// that are already on screen.
    /// 0° points right and positive angles point upward in CurvedText.
    private let dispersionSequence: [Double] = [
        0,
        28, -28,
        14, -14,
        42, -42,
        7, -7,
        21, -21,
        35, -35,
        48, -48
    ]

    /// Maximum radius: from vinyl center to the furthest screen corner.
    private var maxRadius: CGFloat {
        // Distance from vinyl center to top-right corner of screen
        let dx = screenWidth - vinylCenterX
        let dy = max(vinylCenterY, (screenHeight.map { $0 * 0.82 } ?? vinylCenterY * 2) - vinylCenterY)
        return sqrt(dx * dx + dy * dy)
    }

    /// Dynamic ring spacing that fills the available space from vinyl edge to screen corner.
    private var ringSpacing: CGFloat {
        let availableSpace = maxRadius - vinylRadius - 20 // 20pt inner gap
        let lineCount = CGFloat(max(1, maxVisibleLines))
        return availableSpace / lineCount
    }

    var body: some View {
        ZStack {
            // Curved lyric lines — WiFi-style: all arcs centered on same direction
            ForEach(visibleRange, id: \.self) { index in
                let distance = currentIndex - index   // 0 = current, positive = older
                let style = rippleStyle(distance: distance)
                let radius = radiusForLine(index)
                let direction = distance == 0
                    ? arcStartAngle
                    : directionForLine(index, radius: radius)

                if radius > vinylRadius {
                    if distance == 0 {
                        CurvedKaraokeText(
                            text: lines[index],
                            radius: radius,
                            centerX: vinylCenterX,
                            centerY: vinylCenterY,
                            centerAngle: direction,
                            fontSize: style.fontSize * appearance.scale,
                            weight: style.weight,
                            fillProgress: intraLineProgress,
                            markerFillProgress: markerIntraLineProgress,
                            appearance: appearance,
                            words: timedLines.indices.contains(index) ? timedLines[index].words : [],
                            playbackAnchor: playbackAnchor,
                            nextLineStartMs: timedLines.indices.contains(index + 1) ? Int(timedLines[index + 1].startTime * 1000) : nil
                        )
                        .equatable()
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94))
                        )
                    } else {
                        CurvedText(
                            text: lines[index],
                            radius: radius,
                            centerX: vinylCenterX,
                            centerY: vinylCenterY,
                            centerAngle: direction,
                            fontSize: style.fontSize * appearance.scale,
                            weight: style.weight,
                            opacity: style.opacity,
                            blur: style.blur,
                            appearance: appearance
                        )
                        .equatable()
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94))
                        )
                    }
                }
            }

        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)
    }

    // MARK: - Radius Computation

    /// Current line = innermost ring (just outside vinyl).
    /// Older (past) lines expand outward — like ripples radiating from the vinyl.
    private func radiusForLine(_ index: Int) -> CGFloat {
        let innerGap: CGFloat = 48  // keep current lyric clear of the platter edge
        let firstRingExtraGap: CGFloat = 24
        let baseRadius = vinylRadius + innerGap
        let distance = CGFloat(currentIndex - index) // 0 for current, positive for older
        let separation = distance > 0 ? firstRingExtraGap : 0
        return baseRadius + distance * ringSpacing + separation
    }

    // MARK: - Helpers

    /// Current + past (already sung) lines. Current = innermost ring,
    /// older lines ripple outward — creating the expanding ripple effect.
    private var visibleRange: Range<Int> {
        let pastCount = appearance.visibleCount.map { max(0, $0 - 1) } ?? maxVisibleLines
        let start = max(0, currentIndex - pastCount)
        let end = min(lines.count, currentIndex + 1)
        guard start < end else { return 0..<0 }
        return start..<end
    }

    /// Stable direction derived from the lyric's own index. Existing lyrics do
    /// not change direction when `currentIndex` advances.
    private func directionForLine(_ index: Int, radius: CGFloat) -> Double {
        // Keep a lyric's direction stable throughout its outward travel.
        // Changing it at a radius threshold produced detached text at the bottom.
        return dispersionAngle(for: index)
    }

    private func dispersionAngle(for index: Int) -> Double {
        guard !dispersionSequence.isEmpty else { return arcStartAngle }
        let sequenceIndex = abs(index) % dispersionSequence.count
        return dispersionSequence[sequenceIndex]
    }

    private struct RippleStyle {
        let fontSize: CGFloat
        let opacity: Double
        let weight: Font.Weight
        let blur: CGFloat
        let scale: CGFloat
    }

    private func rippleStyle(distance: Int) -> RippleStyle {
        let d = abs(distance)
        let opacity = max(0.18, pow(0.80, Double(d)))

        switch d {
        case 0:  return RippleStyle(fontSize: 26, opacity: 1.0,    weight: .bold,     blur: 0,   scale: 1.0)
        case 1:  return RippleStyle(fontSize: 21, opacity: opacity, weight: .semibold, blur: 0.5, scale: 0.95)
        case 2:  return RippleStyle(fontSize: 19, opacity: opacity, weight: .medium,   blur: 1.2, scale: 0.90)
        case 3:  return RippleStyle(fontSize: 17, opacity: opacity, weight: .regular,  blur: 2.0, scale: 0.85)
        default: return RippleStyle(fontSize: 15, opacity: opacity, weight: .regular,  blur: 2.2, scale: 0.80)
        }
    }
}

// MARK: - Curved Text (characters placed along arc)

/// Renders text along a circular arc, CENTERED around `centerAngle`.
/// Like a WiFi arc — text is symmetrically distributed around the direction.
struct CurvedText: View, Equatable {
    let text: String
    let radius: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let centerAngle: Double   // degrees, text centered around this direction
    let fontSize: CGFloat
    let weight: Font.Weight
    let opacity: Double
    let blur: CGFloat
    var appearance = LyricTextAppearance()

    var body: some View {
        let layout = CurvedGlyphLayout(
            text: text,
            fontSize: fontSize,
            weight: (appearance.weight?.weight ?? weight).uiFontWeight,
            design: appearance.design
        )

        CurvedGlyphCanvas(
            layout: layout, radius: radius, centerX: centerX, centerY: centerY,
            centerAngle: centerAngle,
            font: appearance.font(size: fontSize, weight: weight),
            color: appearance.color ?? .white, opacity: opacity,
            fillProgress: 1, unfilledOpacity: 1, glyphMargin: fontSize
        )
        // Fading distant lyrics avoids a full-surface blur texture per ring.
    }
}

// MARK: - Curved Karaoke Text (with fill progress)

/// Same centered arc placement but with karaoke fill effect:
/// characters up to fillProgress are bright white, rest are dimmed.
struct CurvedKaraokeText: View, Equatable {
    let text: String
    let radius: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let centerAngle: Double
    let fontSize: CGFloat
    let weight: Font.Weight
    let fillProgress: Double
    let markerFillProgress: Double
    var appearance = LyricTextAppearance()
    var words: [SyncedLyricWord] = []
    var playbackAnchor: LyricPlaybackAnchor? = nil
    var nextLineStartMs: Int? = nil

    private var markerStyleSeed: Int {
        text.unicodeScalars.reduce(17) { partial, scalar in
            partial &* 31 &+ Int(scalar.value)
        }
    }

    var body: some View {
        let layout = CurvedGlyphLayout(
            text: text,
            fontSize: fontSize,
            weight: (appearance.weight?.weight ?? weight).uiFontWeight,
            design: appearance.design
        )

        // Center text around centerAngle
        let totalSpanRad = Double(layout.totalWidth) / Double(radius)
        let totalSpanDeg = totalSpanRad * 180 / .pi

        ZStack {
            CurvedMarkerStroke(
                radius: radius,
                centerX: centerX,
                centerY: centerY,
                centerAngle: centerAngle,
                angularSpan: totalSpanDeg,
                lineWidth: fontSize * 1.12,
                fillProgress: markerFillProgress,
                styleSeed: markerStyleSeed
            )

            if let playbackAnchor, !words.isEmpty, words.map(\.text).joined() == text {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playbackAnchor.isPlaying)) { timeline in
                    CurvedGlyphCanvas(
                        layout: layout, radius: radius, centerX: centerX, centerY: centerY,
                        centerAngle: centerAngle, font: appearance.font(size: fontSize, weight: weight),
                        color: appearance.color ?? .black, opacity: 1, fillProgress: fillProgress,
                        unfilledOpacity: 0.38, glyphMargin: fontSize,
                        words: KaraokeFill.tailClamped(words, nextLineStartMs: nextLineStartMs),
                        currentMs: playbackAnchor.milliseconds(at: timeline.date)
                    )
                }
            } else {
            CurvedGlyphCanvas(
                layout: layout, radius: radius, centerX: centerX, centerY: centerY,
                centerAngle: centerAngle,
                font: appearance.font(size: fontSize, weight: weight),
                color: appearance.color ?? .black, opacity: 1,
                fillProgress: fillProgress, unfilledOpacity: 0.38, glyphMargin: fontSize
            )
            }
        }
    }
}

/// One drawing surface per lyric instead of a SwiftUI subtree per character.
/// Geometry remains animatable when a played lyric moves to the next ring.
private struct CurvedGlyphCanvas: View, Animatable {
    let layout: CurvedGlyphLayout
    var radius: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    var centerAngle: Double
    let font: Font
    let color: Color
    let opacity: Double
    let fillProgress: Double
    let unfilledOpacity: Double
    let glyphMargin: CGFloat
    var words: [SyncedLyricWord] = []
    var currentMs: Int = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(radius, centerAngle) }
        set { radius = newValue.first; centerAngle = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let safeRadius = max(1, radius)
            let start = centerAngle * .pi / 180 + Double(layout.totalWidth / safeRadius) / 2
            let bounds = CGRect(origin: .zero, size: size)
                .insetBy(dx: -glyphMargin, dy: -glyphMargin)
            let fillWidth = CGFloat(min(1, max(0, fillProgress))) * layout.totalWidth
            // Resolve repeated letters once per draw, without creating Text views.
            var glyphs: [Character: GraphicsContext.ResolvedText] = [:]
            var wordRanges: [(word: SyncedLyricWord, range: Range<Int>)] = []
            var cursor = 0
            for word in words {
                let end = cursor + word.text.count
                wordRanges.append((word, cursor..<end)); cursor = end
            }
            for i in layout.characters.indices {
                let angle = start - Double(layout.midpointOffsets[i] / safeRadius)
                let point = CGPoint(x: centerX + safeRadius * cos(angle),
                                    y: centerY - safeRadius * sin(angle))
                guard bounds.contains(point) else { continue }
                let character = layout.characters[i]
                let glyph: GraphicsContext.ResolvedText
                if let cached = glyphs[character] {
                    glyph = cached
                } else {
                    glyph = context.resolve(Text(String(character)).font(font).foregroundColor(color))
                    glyphs[character] = glyph
                }
                var drawing = context
                drawing.opacity = opacity * (words.isEmpty ? (layout.midpointOffsets[i] <= fillWidth ? 1 : unfilledOpacity) : 1)
                drawing.translateBy(x: point.x, y: point.y)
                drawing.rotate(by: .radians(.pi / 2 - angle))
                if let timing = wordRanges.first(where: { $0.range.contains(i) }),
                   let last = timing.range.last, last < layout.characters.count {
                    let first = timing.range.lowerBound
                    let start = layout.midpointOffsets[first] - layout.widths[first] / 2
                    let end = layout.midpointOffsets[last] + layout.widths[last] / 2
                    let fraction = KaraokeFill.fillFraction(for: timing.word, atMs: currentMs)
                    let stops = KaraokeFill.stops(left: fraction - KaraokeFill.wordEdgeSoftenBand,
                                                 right: fraction + KaraokeFill.wordEdgeSoftenBand)
                    let p = min(1, max(0, Double(currentMs - timing.word.startMs) / min(1000, Double(max(1, timing.word.durationMs)))))
                    let lift = (glyphMargin * 0.05 * displayScale).rounded() / max(1, displayScale)
                    drawing.translateBy(x: 0, y: reduceMotion ? 0 : -sin(p * .pi / 2) * lift)
                    drawing.drawLayer { layer in
                        layer.draw(glyph, at: .zero, anchor: .center)
                        layer.blendMode = .destinationOut
                        let rect = CGRect(x: -layout.widths[i] / 2 - 2, y: -glyphMargin, width: layout.widths[i] + 4, height: glyphMargin * 2)
                        layer.fill(Path(rect), with: .linearGradient(
                            Gradient(stops: stops.map { .init(color: .white.opacity((1 - $0.intensity) * (1 - unfilledOpacity)), location: $0.location) }),
                            startPoint: CGPoint(x: start - layout.midpointOffsets[i], y: 0),
                            endPoint: CGPoint(x: end - layout.midpointOffsets[i], y: 0)))
                    }
                } else { drawing.draw(glyph, at: .zero, anchor: .center) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Linear-time glyph metrics shared by the curved text renderers. The previous
/// implementation repeatedly summed every preceding glyph for every glyph,
/// turning each line's layout into O(n²) work.
@MainActor
private struct CurvedGlyphLayout {
    private static var cache: [String: CurvedGlyphLayout] = [:]
    let characters: [Character]
    let midpointOffsets: [CGFloat]
    let widths: [CGFloat]
    let totalWidth: CGFloat

    init(text: String, fontSize: CGFloat, weight: UIFont.Weight, design: ShareFontDesign? = nil) {
        let key = "\(fontSize)|\(weight.rawValue)|\(design?.rawValue ?? "rounded")|\(text)"
        if let cached = Self.cache[key] { self = cached; return }
        characters = Array(text)
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let font: UIFont
        if let name = design?.customFontName, let custom = UIFont(name: name, size: fontSize) {
            let descriptor = custom.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            font = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            let mapped: UIFontDescriptor.SystemDesign = switch design {
            case .serif: .serif
            case .monospaced: .monospaced
            case .standard: .default
            default: .rounded
            }
            font = UIFont(descriptor: systemFont.fontDescriptor.withDesign(mapped) ?? systemFont.fontDescriptor,
                          size: fontSize)
        }

        var runningWidth: CGFloat = 0
        var offsets: [CGFloat] = []
        var measuredWidths: [CGFloat] = []
        offsets.reserveCapacity(characters.count)

        for character in characters {
            let width = (String(character) as NSString)
                .size(withAttributes: [.font: font])
                .width
            offsets.append(runningWidth + width / 2)
            measuredWidths.append(width)
            runningWidth += width
        }

        midpointOffsets = offsets
        widths = measuredWidths
        totalWidth = runningWidth
        if Self.cache.count >= 128 { Self.cache.removeAll(keepingCapacity: true) }
        Self.cache[key] = self
    }
}

// MARK: - Curved marker highlight

/// Two slightly uneven translucent passes following the lyric arc. Drawing one
/// continuous stroke behind the glyphs keeps the handwritten marker character
/// without turning every curved character into a separate yellow box.
struct CurvedMarkerStroke: View {
    let radius: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let centerAngle: Double
    let angularSpan: Double
    let lineWidth: CGFloat
    var fillProgress: Double = 1
    var styleSeed = 0

    private let markerColor = Color(red: 1.0, green: 0.93, blue: 0.22)

    private var style: Int {
        let remainder = styleSeed % 4
        return remainder >= 0 ? remainder : remainder + 4
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(1, max(0, fillProgress)))
    }

    private var visibleProgress: CGFloat {
        guard clampedProgress > 0 else { return 0 }
        let arcLength = max(1, radius * CGFloat(angularSpan * .pi / 180))
        let minimumNibProgress = min(0.08, lineWidth * 0.42 / arcLength)
        return max(clampedProgress, minimumNibProgress)
    }

    var body: some View {
        ZStack {
            markerPath(radialOffset: 0, phase: 0)
                .trim(from: 0, to: visibleProgress)
                .stroke(
                    markerColor.opacity([0.50, 0.56, 0.48, 0.53][style]),
                    style: StrokeStyle(
                        lineWidth: lineWidth * [1.0, 0.92, 1.08, 0.97][style],
                        lineCap: .butt,
                        lineJoin: .round
                    )
                )

            markerPath(
                radialOffset: [1.5, -0.8, 2.2, 0.6][style],
                phase: [.pi / 3, .pi / 5, .pi / 2, .pi / 7][style]
            )
                .trim(from: 0, to: visibleProgress)
                .stroke(
                    markerColor.opacity([0.13, 0.17, 0.11, 0.15][style]),
                    style: StrokeStyle(
                        lineWidth: lineWidth * [0.70, 0.62, 0.76, 0.66][style],
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .blendMode(.multiply)

            if visibleProgress > 0 {
                markerEndPoolPath(progress: Double(visibleProgress))
                    .fill(markerColor.opacity([0.17, 0.21, 0.15, 0.19][style]))
                    .blendMode(.multiply)
            }
        }
        .allowsHitTesting(false)
    }

    private func markerPath(radialOffset: CGFloat, phase: Double) -> Path {
        let padding = max(4, lineWidth * 0.30)
        let paddedSpan = angularSpan + Double(padding / max(radius, 1)) * 180 / .pi * 2
        let startAngle = centerAngle + paddedSpan / 2
        let samples = max(18, Int(paddedSpan / 2.5))

        var path = Path()
        for sample in 0...samples {
            let progress = Double(sample) / Double(samples)
            let angle = startAngle - paddedSpan * progress
            let angleRadians = angle * .pi / 180
            let frequency = [5.0, 4.0, 6.5, 5.75][style]
            let amplitude: CGFloat = [0.8, 0.55, 1.05, 0.7][style]
            let wobble = CGFloat(sin(progress * .pi * frequency + phase)) * amplitude
            let pointRadius = radius + radialOffset + wobble
            let point = CGPoint(
                x: centerX + pointRadius * cos(CGFloat(angleRadians)),
                y: centerY - pointRadius * sin(CGFloat(angleRadians))
            )

            if sample == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }

    private func markerEndPoolPath(progress: Double) -> Path {
        let padding = max(4, lineWidth * 0.30)
        let paddedSpan = angularSpan + Double(padding / max(radius, 1)) * 180 / .pi * 2
        let startAngle = centerAngle + paddedSpan / 2
        let endAngle = startAngle - paddedSpan * progress
        let angleRadians = endAngle * .pi / 180
        let endPoint = CGPoint(
            x: centerX + radius * cos(CGFloat(angleRadians)),
            y: centerY - radius * sin(CGFloat(angleRadians))
        )
        let poolSize = lineWidth * [0.92, 0.80, 1.02, 0.87][style]
        // Move the ink pool backwards along the stroke tangent. Its leading
        // edge now ends at the original marker endpoint instead of passing it.
        let previousAngleRadians = (endAngle + 0.5) * .pi / 180
        let previousPoint = CGPoint(
            x: centerX + radius * cos(CGFloat(previousAngleRadians)),
            y: centerY - radius * sin(CGFloat(previousAngleRadians))
        )
        let tangentX = endPoint.x - previousPoint.x
        let tangentY = endPoint.y - previousPoint.y
        let tangentLength = max(hypot(tangentX, tangentY), 0.001)
        let poolCenter = CGPoint(
            x: endPoint.x - tangentX / tangentLength * poolSize * 0.55,
            y: endPoint.y - tangentY / tangentLength * poolSize * 0.55
        )
        return Path(
            ellipseIn: CGRect(
                x: poolCenter.x - poolSize * 0.50,
                y: poolCenter.y - poolSize * 0.54,
                width: poolSize,
                height: poolSize * 1.08
            )
        )
    }
}

// MARK: - UIFont Weight Bridge

extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}

// MARK: - Ripple Ring Effect

struct RippleRingEffect: View {
    let center: CGPoint
    let baseRadius: CGFloat
    let trigger: Int

    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(ringOpacity), lineWidth: 1.2)
            .frame(
                width: baseRadius * 2 * ringScale,
                height: baseRadius * 2 * ringScale
            )
            .position(x: center.x, y: center.y)
            .onChange(of: trigger) { _, _ in
                ringScale = 1.0
                ringOpacity = 0.35
                withAnimation(.easeOut(duration: 0.9)) {
                    ringScale = 1.12
                    ringOpacity = 0
                }
            }
    }
}

// MARK: - Custom Transition

extension AnyTransition {
    static var rippleIn: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 1.05).combined(with: .opacity)
        )
    }
}
