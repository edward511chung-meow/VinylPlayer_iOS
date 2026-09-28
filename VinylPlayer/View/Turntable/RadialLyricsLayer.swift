import SwiftUI

/// Optional share-card overrides; nil keeps the player's existing appearance.
struct LyricTextAppearance: Equatable {
    var scale: CGFloat = 1
    var design: ShareFontDesign? = nil
    var weight: ShareFontWeight? = nil
    var color: Color? = nil
    var visibleCount: Int? = nil

    func font(size: CGFloat, weight fallback: Font.Weight) -> Font {
        let resolvedWeight = weight?.weight ?? fallback
        return design?.font(size: size, weight: resolvedWeight)
            ?? .system(size: size, weight: resolvedWeight, design: .rounded)
    }
}

/// 手動調整歌詞間距，單位為 pt；數值越細越密。
enum RadialLyricSpacing {
    /// 當前歌詞及附近段落之間的留白，不會隨換行數增加。
    static let lineGap: CGFloat = 12
    /// 前後較遠端歌詞的留白，兩個方向使用同一設定。
    static let distantLineGap: CGFloat = 6
    /// 相鄰兩段都距離當前歌詞至少兩段時，使用遠端間距。
    static let distantFromIndex = 2
    /// 同一段歌詞自動換行後，額外加入的行距。
    static let wrappedLineSpacing: CGFloat = 0
}

/// One broad circular arc drives both row placement and text orientation.
enum RadialLyricCurve {
    nonisolated static func radius(canvasWidth: CGFloat) -> CGFloat {
        max(1, canvasWidth) * 1.2
    }

    nonisolated static func textAngle(verticalOffset: CGFloat, canvasWidth: CGFloat,
                                     textLeftEdge: CGFloat) -> Angle {
        let radius = radius(canvasWidth: canvasWidth)
        return .radians(asin(Double(min(1, max(-1, verticalOffset / radius)))))
    }
}

/// Shared by Full Player and share cards. Text follows the arc's outward normal
/// while retaining its measured wrapping and spacing along the leading edge.
struct RadialLyricsLayer: View {
    var timedLines: [LyricLine] = []
    var playbackAnchor: LyricPlaybackAnchor? = nil
    let lines: [String]
    let currentIndex: Double
    let intraLineProgress: Double
    var markerIntraLineProgress: Double = 1
    var isInteractive: Bool = false
    var appearance = LyricTextAppearance()
    let vinylCenterX: CGFloat
    let vinylCenterY: CGFloat
    let vinylRadius: CGFloat
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat

    private let edgePadding: CGFloat = 12
    @Namespace private var lyricCoordinateSpace

    var body: some View {
        let textLeftEdge = vinylCenterX + vinylRadius + 24
        let textWidth = max(80, canvasWidth - textLeftEdge - edgePadding)
        let clampedIndex = min(max(0, currentIndex), Double(max(0, lines.count - 1)))
        let activeIndex = Int(round(clampedIndex))
        // Include enough one-line rows to cover the longest visible arc, plus
        // an overscan margin for animated line changes. Wrapped rows need less.
        let extent = max(abs(vinylCenterY), abs(canvasHeight - vinylCenterY))
        let radius = RadialLyricCurve.radius(canvasWidth: canvasWidth)
        let arcLength = radius * asin(min(1, extent / radius))
            + max(0, extent - radius)
        let rowBudget = Int(ceil(arcLength / max(1, 24 * appearance.scale))) + 4
        let start = max(0, activeIndex - rowBudget)
        let end = min(lines.count, activeIndex + rowBudget + 1)

        RadialLyricColumnLayout(
            currentIndex: clampedIndex,
            textLeftEdge: textLeftEdge,
            textWidth: textWidth,
            centerY: vinylCenterY,
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
            firstIndex: start
        ) {
            ForEach(start..<end, id: \.self) { index in
                lyric(lines[index], distance: abs(index - activeIndex), textWidth: textWidth)
                    .opacity(isVisible(index, activeIndex: activeIndex) ? 1 : 0)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .coordinateSpace(name: lyricCoordinateSpace)
        .clipped()
        .animation(isInteractive ? nil : .smooth(duration: 0.42), value: clampedIndex)
    }

    @ViewBuilder
    private func lyric(_ line: String, distance: Int, textWidth: CGFloat) -> some View {
        let style = lyricStyle(distance: distance)
        let coordinateSpace = lyricCoordinateSpace
        let centerY = vinylCenterY
        let width = canvasWidth
        let textLeftEdge = vinylCenterX + vinylRadius + 24
        Group {
            if distance == 0 {
                KaraokeLyricText(
                    text: line,
                    fillProgress: intraLineProgress,
                    markerFillProgress: markerIntraLineProgress,
                    fontSize: style.fontSize * appearance.scale,
                    weight: style.weight,
                    filledColor: appearance.color ?? .black,
                    unfilledColor: Color.black.opacity(0.38),
                    maxWidth: textWidth,
                    showsHandwrittenHighlight: true,
                    fontOverride: appearance.font(size: style.fontSize * appearance.scale, weight: style.weight),
                    words: timedLines.indices.contains(Int(currentIndex.rounded())) ? timedLines[Int(currentIndex.rounded())].words : [],
                    playbackAnchor: playbackAnchor,
                    nextLineStartMs: timedLines.indices.contains(Int(currentIndex.rounded()) + 1) ? Int(timedLines[Int(currentIndex.rounded()) + 1].startTime * 1000) : nil
                )
                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
            } else {
                Text(line)
                    .font(appearance.font(size: style.fontSize * appearance.scale, weight: style.weight))
                    .foregroundColor((appearance.color ?? .white).opacity(style.opacity))
                    .shadow(color: Color.white.opacity(0.4), radius: 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lineSpacing(RadialLyricSpacing.wrappedLineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blur(radius: style.blur)
        // Rotate only the rendered result, around the existing arc position.
        // Measure wrapping before rotation; the layout spaces those measured
        // heights along the arc rather than stretching their vertical offsets.
        .visualEffect { content, geometry in
            let rowCenterY = geometry.frame(in: .named(coordinateSpace)).midY
            return content.rotationEffect(
                RadialLyricCurve.textAngle(verticalOffset: rowCenterY - centerY,
                                          canvasWidth: width,
                                          textLeftEdge: textLeftEdge),
                anchor: .leading
            )
        }
    }

    private func isVisible(_ index: Int, activeIndex: Int) -> Bool {
        guard let requestedCount = appearance.visibleCount else { return true }
        let count = max(1, min(requestedCount, lines.count))
        let start = min(max(0, activeIndex - (count - 1) / 2), max(0, lines.count - count))
        return index >= start && index < start + count
    }

    private func lyricStyle(distance: Int) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat) {
        switch distance {
        case 0:  return (26, 1.0,  .bold,     0)
        case 1:  return (24, 0.64, .semibold, 0.64)
        case 2:  return (24, 0.56, .medium,   1.2)
        case 3:  return (24, 0.40, .regular,  1.6)
        case 4:  return (24, 0.32, .regular,  2.4)
        default: return (24, 0.24, .regular, 3.0)
        }
    }
}

/// Measure and place the same SwiftUI views at the same width. A wrapped lyric
/// contributes its actual height, plus just one inter-lyric gap.
struct RadialLyricColumnLayout: Layout {
    var currentIndex: Double
    var animatableData: Double {
        get { currentIndex }
        set { currentIndex = newValue }
    }
    let textLeftEdge: CGFloat
    let textWidth: CGFloat
    let centerY: CGFloat
    let canvasSize: CGSize
    var firstIndex: Int = 0

    struct Cache {
        var heights: [CGFloat]
        var width: CGFloat
        var rowWidths: [CGFloat]
        var activeIndex: Int
    }

    func makeCache(subviews: Subviews) -> Cache {
        let active = Int(currentIndex.rounded())
        var layout = self
        layout.currentIndex = Double(active)
        var widths = Array(repeating: textWidth, count: subviews.count)
        var heights = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height
        }
        // Resolve wrapping against the arc's available horizontal space.
        // Limit measurement to discrete lyric changes, not animation frames.
        for _ in 0..<3 {
            let tops = layout.rowTops(heights: heights)
            for index in subviews.indices {
                let y = layout.verticalOffset(forArcDistance: tops[index] + heights[index] / 2 - centerY)
                widths[index] = index + firstIndex == active ? textWidth
                    : availableTextWidth(verticalOffset: y, rowHeight: heights[index])
                heights[index] = subviews[index].sizeThatFits(
                    ProposedViewSize(width: widths[index], height: nil)).height
            }
        }
        return Cache(heights: heights, width: textWidth, rowWidths: widths, activeIndex: active)
    }

    func availableTextWidth(verticalOffset: CGFloat, rowHeight: CGFloat) -> CGFloat {
        let angle = RadialLyricCurve.textAngle(verticalOffset: verticalOffset,
            canvasWidth: canvasSize.width, textLeftEdge: textLeftEdge).radians
        let left = textLeftEdge + horizontalCurveOffset(at: centerY + verticalOffset)
        let sideRoom = canvasSize.width - 12 - left - abs(sin(angle)) * rowHeight / 2
        let projectedWidth = sideRoom / max(0.25, cos(angle))
        return max(textWidth, min(canvasSize.width * 0.95, projectedWidth))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        canvasSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.width != textWidth || cache.heights.count != subviews.count
            || cache.activeIndex != Int(currentIndex.rounded()) {
            updateCache(&cache, subviews: subviews)
        }
        let heights = cache.heights
        let tops = rowTops(heights: heights)
        for index in subviews.indices {
            let measuredCenter = tops[index] + heights[index] / 2
            let rowCenterY = centerY + verticalOffset(forArcDistance: measuredCenter - centerY)
            subviews[index].place(
                at: CGPoint(x: bounds.minX + textLeftEdge + horizontalCurveOffset(at: rowCenterY),
                            y: bounds.minY + rowCenterY - heights[index] / 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cache.rowWidths[index], height: nil)
            )
        }
    }

    /// Use true arc length: the same radius controls position and rotation.
    func verticalOffset(forArcDistance distance: CGFloat) -> CGFloat {
        let radius = RadialLyricCurve.radius(canvasWidth: canvasSize.width)
        let arc = abs(distance)
        let halfCircle = radius * .pi / 2
        // Keep offscreen rows outside the viewport instead of wrapping around.
        let y = arc <= halfCircle ? radius * sin(arc / radius) : radius + arc - halfCircle
        return distance < 0 ? -y : y
    }

    func horizontalCurveOffset(at rowCenterY: CGFloat) -> CGFloat {
        let radius = RadialLyricCurve.radius(canvasWidth: canvasSize.width)
        let y = min(radius, abs(rowCenterY - centerY))
        return sqrt(max(0, radius * radius - y * y)) - radius
    }

    func rowTops(heights: [CGFloat]) -> [CGFloat] {
        guard !heights.isEmpty else { return [] }
        let index = min(max(0, currentIndex - Double(firstIndex)), Double(heights.count - 1))
        var tops = Array(repeating: CGFloat.zero, count: heights.count)
        for row in 1..<heights.count {
            // Blend the two endpoint layouts instead of switching spacing at
            // a rounded index halfway through a drag or playback transition.
            func gap(at active: Int) -> CGFloat {
                let nearest = min(abs(row - 1 - active), abs(row - active))
                return nearest >= RadialLyricSpacing.distantFromIndex
                    ? RadialLyricSpacing.distantLineGap : RadialLyricSpacing.lineGap
            }
            let lower = Int(floor(index))
            let blend = CGFloat(index - Double(lower))
            let gap = gap(at: lower) + (gap(at: min(lower + 1, heights.count - 1)) - gap(at: lower)) * blend
            tops[row] = tops[row - 1] + heights[row - 1] + gap
        }

        // Center the current lyric; interpolate between measured centers while
        // playback/manual scrolling advances the continuous lyric index.
        let lower = Int(floor(index))
        let upper = min(lower + 1, heights.count - 1)
        let fraction = CGFloat(index - Double(lower))
        let lowerCenter = tops[lower] + heights[lower] / 2
        let upperCenter = tops[upper] + heights[upper] / 2
        let shift = centerY - (lowerCenter + (upperCenter - lowerCenter) * fraction)
        return tops.map { $0 + shift }
    }
}
