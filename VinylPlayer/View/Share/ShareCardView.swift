import SwiftUI
import SwiftData

// MARK: - Share Card Style

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case vinylCover = "vinylCover"
    case turntable = "turntable"
    case lyricsPlayer = "lyricsPlayer"
    case rippleLyrics = "rippleLyrics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinylCover: return L("share.style_vinyl_cover")
        case .turntable: return L("share.style_turntable")
        case .lyricsPlayer: return L("share.style_lyrics")
        case .rippleLyrics: return L("share.style_ripple")
        }
    }

    var iconName: String {
        switch self {
        case .vinylCover: return "record.circle"
        case .turntable: return "dot.radiowaves.up.forward"
        case .lyricsPlayer: return "quote.bubble"
        case .rippleLyrics: return "wifi"
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .vinylCover: return 360
        case .turntable: return 400
        case .lyricsPlayer: return 640
        case .rippleLyrics: return 640
        }
    }
}

// MARK: - Share Card Data

struct ShareCardData {
    var album: Album? = nil
    var playbackProgress: Double = 0
    var isPlaying: Bool = false
    var rpm: Double = AppConstants.rpm33
    var tonearmColor: Color = .gray
    var needleLifted: Bool = false
    var needleParked: Bool = false
    var lyricFillProgress: Double = 1
    var lyricMarkerProgress: Double = 1
    let albumTitle: String
    let artist: String
    let trackTitle: String?
    let coverImage: UIImage?
    let accentColor: Color
    let year: Int?
    let lyrics: [String]?
    let currentLyricIndex: Int?
    let lyricLines: [LyricLine]?  // synced lyrics with timestamps for video
    let baseStyle: TurntableBaseStyle

    /// Whether lyrics data is available for the lyrics player style
    var hasLyrics: Bool {
        guard let lyrics, let idx = currentLyricIndex else { return false }
        return !lyrics.isEmpty && idx >= 0 && idx < lyrics.count
    }

    /// Whether synced (timestamped) lyrics are available for video export
    var hasSyncedLyrics: Bool {
        guard let lines = lyricLines else { return false }
        return lines.count > 1 && lines.contains(where: { $0.startTime > 0 })
    }
}

// MARK: - Share Card View

struct ShareCardView: View {
    let data: ShareCardData
    let style: ShareCardStyle
    @ObservedObject var customization: ShareCustomization = ShareCustomization()
    var vinylRotationAngle: Double = 0  // for video frame rendering
    var overrideLyricIndex: Int? = nil  // for video frame rendering
    var overrideLyricProgress: Double? = nil  // fractional index for smooth video transitions

    private let cardWidth: CGFloat = 360

    /// Effective cover: custom upload or original album cover
    private var effectiveCover: UIImage? {
        customization.customCoverImage ?? data.coverImage
    }

    private var shareLyricFontScale: CGFloat {
        min(1.55, max(0.7, customization.titleFontSize / 18.0))
    }

    private var lyricAppearance: LyricTextAppearance {
        LyricTextAppearance(scale: shareLyricFontScale,
                            design: customization.overridesFontDesign ? customization.fontDesign : nil,
                            weight: customization.overridesFontWeight ? customization.fontWeight : nil,
                            color: customization.overridesTextColor ? customization.textColor : nil,
                            visibleCount: customization.lyricsLineCount)
    }

    private var shareTrackInfoBackdrop: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: data.accentColor.opacity(0.28), location: 0),
                        .init(color: data.accentColor.opacity(0.14), location: 0.44),
                        .init(color: data.accentColor.opacity(0.05), location: 0.74),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 150
                )
            )
            .frame(width: 300, height: 84)
            .blur(radius: 9)
            .allowsHitTesting(false)
    }

    var body: some View {
        Group {
            switch style {
            case .vinylCover:
                vinylCoverCard
            case .turntable:
                turntableCard
            case .lyricsPlayer:
                lyricsPlayerCard
            case .rippleLyrics:
                rippleLyricsCard
            }
        }
        .frame(width: cardWidth, height: style.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Style 1: Vinyl Cover (cover + half-exposed disc)

    private var vinylCoverCard: some View {
        let coverSize: CGFloat = 160
        let discSize: CGFloat = coverSize * 1.0

        return ZStack {
            cardBackground(width: cardWidth, height: style.cardHeight)

            VStack(spacing: 16) {
                Spacer()

                // Cover + Vinyl centered
                let discExposure: CGFloat = 55
                let groupWidth = coverSize + discExposure

                ZStack {
                    // Vinyl disc (right half)
                    ZStack {
                        vinylDisc(size: discSize)

                        // Center label — album cover
                        if let img = effectiveCover {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: discSize * 0.38, height: discSize * 0.38)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        } else {
                            Circle()
                                .fill(data.accentColor.opacity(0.8))
                                .frame(width: discSize * 0.38, height: discSize * 0.38)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white.opacity(0.7))
                                )
                        }

                        // Spindle hole
                        spindleHole(discSize: discSize)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 8, x: -4)
                    .offset(x: discExposure + 20)

                    // Album cover (left half)
                    Group {
                        if let img = effectiveCover {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: coverSize, height: coverSize)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(data.accentColor.opacity(0.6))
                                .frame(width: coverSize, height: coverSize)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white.opacity(0.7))
                                )
                        }
                    }
                }
                .frame(width: groupWidth, height: coverSize)

                // Text info
                VStack(spacing: 4) {
                    titleText(data.trackTitle ?? data.albumTitle)
                    subtitleText(data.artist)
                    if data.trackTitle != nil {
                        captionText(data.albumTitle)
                    }
                }
                .padding(.horizontal, 24)

                brandingFooter
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Style 2: Turntable (full base + vinyl + tonearm)

    private var turntableCard: some View {
        let vinylSize: CGFloat = 200
        let centerX: CGFloat = cardWidth / 2
        let centerY: CGFloat = 170

        return ZStack {
            cardBackground(width: cardWidth, height: style.cardHeight)
            shareLyricsHardware(vinylSize: vinylSize, centerX: centerX, centerY: centerY,
                                showsLyrics: false)

            // Bottom info + branding
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 4) {
                    titleText(data.trackTitle ?? data.albumTitle)
                    subtitleText(data.artist)
                    if data.trackTitle != nil {
                        captionText(data.albumTitle)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                brandingFooter
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Style 3: Lyrics Player (turntable + radial lyrics)

    private var lyricsPlayerCard: some View {
        let vinylSize: CGFloat = cardWidth * 1.14
        let vinylCenterX: CGFloat = -cardWidth * 0.08 + 16
        let vinylCenterY: CGFloat = style.cardHeight * 0.38

        return ZStack {
            cardBackground(width: cardWidth, height: style.cardHeight)

            shareLyricsHardware(vinylSize: vinylSize, centerX: vinylCenterX, centerY: vinylCenterY)

            // Reuse the exact same lyric renderer as the full player.
            if let lyrics = data.lyrics,
               let currentIdx = overrideLyricIndex ?? data.currentLyricIndex,
               !lyrics.isEmpty, currentIdx >= 0, currentIdx < lyrics.count {
                RadialLyricsLayer(
                    lines: lyrics,
                    currentIndex: overrideLyricProgress ?? Double(currentIdx),
                    intraLineProgress: overrideLyricProgress == nil ? data.lyricFillProgress : 1,
                    // A static card must show the finished marker, even when
                    // opened during the intro or the live stroke's first frame.
                    markerIntraLineProgress: 1,
                    appearance: lyricAppearance,
                    vinylCenterX: vinylCenterX,
                    vinylCenterY: vinylCenterY,
                    vinylRadius: vinylSize / 2,
                    canvasWidth: cardWidth,
                    canvasHeight: style.cardHeight
                )
            }

            // Bottom info
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    titleText(data.trackTitle ?? data.albumTitle)
                        .multilineTextAlignment(.trailing)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    subtitleText(data.artist)
                    if data.trackTitle != nil {
                        captionText(data.albumTitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(alignment: .trailing) {
                    shareTrackInfoBackdrop
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                brandingFooter
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Style 4: Ripple Lyrics (same layout as lyricsPlayer, curved arcs instead of radial)

    private var rippleLyricsCard: some View {
        let vinylSize: CGFloat = cardWidth * 1.14
        let vinylCenterX: CGFloat = -cardWidth * 0.08 + 16
        let vinylCenterY: CGFloat = style.cardHeight * 0.38

        return ZStack {
            cardBackground(width: cardWidth, height: style.cardHeight)

            shareLyricsHardware(vinylSize: vinylSize, centerX: vinylCenterX, centerY: vinylCenterY)

            // Reuse the exact same ripple renderer as the full player.
            if let lyrics = data.lyrics,
               let currentIdx = overrideLyricIndex ?? data.currentLyricIndex,
               !lyrics.isEmpty, currentIdx >= 0, currentIdx < lyrics.count {
                RippleLyricsLayer(
                    lines: lyrics,
                    currentIndex: currentIdx,
                    intraLineProgress: 1,
                    appearance: lyricAppearance,
                    vinylCenterX: vinylCenterX,
                    vinylCenterY: vinylCenterY,
                    vinylRadius: vinylSize / 2,
                    screenWidth: cardWidth,
                    screenHeight: style.cardHeight
                )
            }

            // Bottom info
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    titleText(data.trackTitle ?? data.albumTitle)
                        .multilineTextAlignment(.trailing)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    subtitleText(data.artist)
                    if data.trackTitle != nil {
                        captionText(data.albumTitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(alignment: .trailing) {
                    shareTrackInfoBackdrop
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                brandingFooter
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Ripple Curved Lyrics (WiFi-style arcs for share card)

    private func shareRippleLyrics(
        lyrics: [String],
        currentIndex: Double,
        centerX: CGFloat,
        centerY: CGFloat,
        vinylRadius: CGFloat
    ) -> some View {
        let visibleCount = max(1, min(13, customization.lyricsLineCount))
        let maxVisible = visibleCount - 1
        let innerGap: CGFloat = 48
        let firstRingExtraGap: CGFloat = 24
        let focalAngle: Double = 15
        let clampedProgress = min(max(0, currentIndex), Double(lyrics.count - 1))
        let floorIndex = Int(floor(clampedProgress))
        let transitionFraction = clampedProgress - Double(floorIndex)
        let activeIndex = transitionFraction > 0.0001
            ? min(lyrics.count - 1, floorIndex + 1)
            : floorIndex

        // Same compact, fixed direction order used by RippleLyricsLayer.
        // A lyric's direction is derived from its own index, so old lyrics do
        // not reshuffle when playback advances.
        let dispersionSequence: [Double] = [
            0,
            28, -28,
            14, -14,
            42, -42,
            7, -7,
            21, -21,
            35, -35,
            48, -48
        ]

        // Show current + past lines (inner to outer)
        let start = max(0, activeIndex - maxVisible)
        let end = min(lyrics.count, activeIndex + 1)

        // Calculate ring spacing to fill available space
        let dx = cardWidth - centerX
        let dy = centerY
        let maxRadius = sqrt(dx * dx + dy * dy)
        let ringSpacing = (maxRadius - vinylRadius - innerGap) / CGFloat(max(1, maxVisible))

        return ZStack {
            ForEach(start..<end, id: \.self) { index in
                let fractionalDist = clampedProgress - Double(index)
                let radius = vinylRadius
                    + innerGap
                    + CGFloat(fractionalDist) * ringSpacing
                    + (fractionalDist > 0 ? firstRingExtraGap : 0)
                let style = shareRippleStyleInterpolated(fractionalDist)
                let stableAngle = dispersionSequence[abs(index) % dispersionSequence.count]
                let direction: Double = {
                    if index == activeIndex {
                        return focalAngle
                    }

                    // During video export, the line that has just finished
                    // eases from the focal point into its permanent slot.
                    if transitionFraction > 0.0001 && index == floorIndex {
                        return focalAngle + (stableAngle - focalAngle) * transitionFraction
                    }

                    return stableAngle
                }()

                if radius > vinylRadius {
                    shareCurvedText(
                        text: lyrics[index],
                        radius: radius,
                        centerX: centerX,
                        centerY: centerY,
                        centerAngle: direction,
                        fontSize: style.fontSize,
                        weight: style.weight,
                        opacity: style.opacity,
                        blur: style.blur,
                        isCurrent: index == activeIndex
                    )
                }
            }
        }
    }

    /// Render text centered along a circular arc (WiFi-style symmetry)
    private func shareCurvedText(
        text: String,
        radius: CGFloat,
        centerX: CGFloat,
        centerY: CGFloat,
        centerAngle: Double,
        fontSize: CGFloat,
        weight: Font.Weight,
        opacity: Double,
        blur: CGFloat,
        isCurrent: Bool = false
    ) -> some View {
        let characters = Array(text)
        let renderedWeight = shareResolvedLyricWeight(weight)
        let font = shareUIFont(size: fontSize, weight: renderedWeight)
        let charWidths = characters.map { char -> CGFloat in
            (String(char) as NSString).size(withAttributes: [.font: font]).width
        }

        // Total angular span
        let totalSpanRad = charWidths.reduce(0.0) { $0 + Double($1) / Double(radius) }
        let totalSpanDeg = totalSpanRad * 180 / .pi
        // Start from centerAngle + half span so text is centered
        let startDeg = centerAngle + totalSpanDeg / 2

        return ZStack {
            if isCurrent {
                CurvedMarkerStroke(
                    radius: radius,
                    centerX: centerX,
                    centerY: centerY,
                    centerAngle: centerAngle,
                    angularSpan: totalSpanDeg,
                    lineWidth: fontSize * 1.12
                )
            }

            ForEach(0..<characters.count, id: \.self) { i in
                let offset = shareAngularOffset(upTo: i, widths: charWidths, radius: radius)
                let angleDeg = startDeg - offset * 180 / .pi
                let angleRad = angleDeg * .pi / 180

                let x = centerX + radius * cos(CGFloat(angleRad))
                let y = centerY - radius * sin(CGFloat(angleRad))

                Text(String(characters[i]))
                    .font(customization.fontDesign.font(size: fontSize, weight: renderedWeight))
                    .foregroundColor(
                        isCurrent
                            ? Color.black.opacity(0.96)
                            : customization.textColor.opacity(opacity)
                    )
                    .shadow(
                        color: isCurrent ? Color.black.opacity(0.10) : .clear,
                        radius: 2,
                        y: 1
                    )
                    .rotationEffect(.degrees(-angleDeg + 90))
                    .position(x: x, y: y)
                    .blur(radius: blur)
            }
        }
    }

    private func shareAngularOffset(upTo index: Int, widths: [CGFloat], radius: CGFloat) -> Double {
        var total: Double = 0
        for i in 0..<index {
            total += Double(widths[i]) / Double(radius)
        }
        if index < widths.count {
            total += Double(widths[index]) / (2 * Double(radius))
        }
        return total
    }

    private func shareRippleStyle(_ distance: Int) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat) {
        let d = abs(distance)
        let opacity = max(0.09, pow(0.72, Double(d)))
        let base: (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat)

        switch d {
        case 0:  base = (26, 1.0,    .bold,     0)
        case 1:  base = (21, opacity, .semibold, 0.5)
        case 2:  base = (19, opacity, .medium,   1.2)
        case 3:  base = (17, opacity, .regular,  2.0)
        default: base = (15, opacity, .regular,  2.2)
        }

        return (base.fontSize * shareLyricFontScale, base.opacity, base.weight, base.blur)
    }

    /// Interpolated style for smooth video transitions using fractional distance
    private func shareRippleStyleInterpolated(_ fractionalDistance: Double) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat) {
        let d = abs(fractionalDistance)
        let lower = Int(floor(d))
        let upper = lower + 1
        let frac = CGFloat(d - Double(lower))

        let s0 = shareRippleStyle(lower)
        let s1 = shareRippleStyle(upper)

        let fontSize = s0.fontSize + (s1.fontSize - s0.fontSize) * frac
        let opacity = s0.opacity + (s1.opacity - s0.opacity) * Double(frac)
        let blur = s0.blur + (s1.blur - s0.blur) * frac
        // Use the weight of the nearest integer distance
        let weight = frac < 0.5 ? s0.weight : s1.weight

        return (fontSize, opacity, weight, blur)
    }

    // MARK: - Static Tonearm (matches TurntableView layout)

    private func shareLyricsHardware(vinylSize: CGFloat, centerX: CGFloat, centerY: CGFloat,
                                     showsLyrics: Bool = true) -> some View {
        let referenceSize: CGFloat = 380
        let scale = vinylSize / referenceSize
        let layout = TurntableHardwareLayout(recordDiameter: referenceSize,
                                             baseReferenceSize: referenceSize * (showsLyrics ? 1 : 0.85 / 0.80),
                                             showsLyrics: showsLyrics)
        let selectorScale = 0.75 * scale
        return ZStack {
            ZStack {
                TurntableBaseView(layout: layout, baseStyle: data.baseStyle, isPlaying: data.isPlaying)
                if !showsLyrics {
                    Circle().fill(Color.black.opacity(0.55))
                        .overlay {
                            Circle().strokeBorder(
                                LinearGradient(colors: [.black.opacity(0.75), .white.opacity(0.25)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 5)
                        }
                        .frame(width: referenceSize + 25, height: referenceSize + 25)
                }
                TurntablePlatterView(recordDiameter: referenceSize,
                                     showsTransparentRecord: customization.overridesVinyl
                                        ? customization.isTranslucent : (data.album?.usesTransparentVinyl ?? false))
                VinylDiscView(album: data.album, size: referenceSize, rotation: vinylRotationAngle,
                              vinylColor: data.album?.selectedEdition?.vinylColor ?? .black,
                              customColorHex: customization.overridesVinyl
                                ? customization.vinylColorHex : data.album?.customVinylColorHex,
                              discOpacityOverride: customization.overridesVinyl
                                ? (customization.isTranslucent ? 0.35 : 1)
                                : (data.album?.effectiveVinylOpacity ?? 1), usesLiveGlass: false,
                              labelArtworkOverride: effectiveCover)
                TurntableTonearmView(layout: layout, progress: data.playbackProgress,
                                    isLifted: .constant(data.needleLifted), isParked: data.needleParked,
                                    tonearmColor: data.tonearmColor, onSeek: { _ in })
            }
            .frame(width: referenceSize, height: referenceSize)
            .rotationEffect(.degrees(showsLyrics ? 0 : 45))
            .scaleEffect(scale)
            .position(x: centerX, y: centerY)

            TurntableSelectorControls(isPlaying: data.isPlaying, rpm: data.rpm,
                                      onTogglePlayback: {}, onToggleSpeed: {})
                .frame(width: 168, height: 48)
                .rotationEffect(.degrees(showsLyrics ? -45 : 0))
                .scaleEffect(selectorScale)
                .position(x: showsLyrics
                          ? (24 / sqrt(2.0) - 9.6) * selectorScale + vinylSize * 0.025
                          : centerX - layout.baseSideLength * scale / 2 + 84 * selectorScale,
                          y: centerY + vinylSize * (showsLyrics ? 0.64 : 0.49))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Customizable Background

    @ViewBuilder
    private func cardBackground(width: CGFloat, height: CGFloat) -> some View {
        switch customization.backgroundStyle {
        case .blurredCover:
            if let img = effectiveCover {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.5))
            } else {
                LinearGradient(
                    colors: [data.accentColor, data.accentColor.opacity(0.3), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .solidColor:
            customization.backgroundColor
        case .gradient:
            LinearGradient(
                colors: [customization.gradientStart, customization.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Customizable Text

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(customization.titleFont)
            .foregroundColor(customization.textColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(customization.subtitleFont)
            .foregroundColor(customization.textColor.opacity(0.8))
            .lineLimit(1)
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(customization.captionFont)
            .foregroundColor(customization.textColor.opacity(0.6))
            .lineLimit(1)
    }

    // MARK: - Spindle Hole

    private func spindleHole(discSize: CGFloat) -> some View {
        Circle()
            .fill(Color.black)
            .frame(width: discSize * 0.025, height: discSize * 0.025)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 1)
    }

    // MARK: - Vinyl Disc

    private func vinylDisc(size: CGFloat) -> some View {
        let grooveCount = 40
        let innerRadius: CGFloat = 0.16  // start grooves after center label
        let outerRadius: CGFloat = 0.95  // leave thin rim
        let vColor = customization.vinylColor
        let discOpacity: Double = customization.isTranslucent ? 0.35 : 1.0

        return ZStack {
            // Disc body + grooves — these rotate
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            vColor.opacity(0.95 * discOpacity),
                            vColor.opacity(discOpacity),
                            vColor.opacity(0.7 * discOpacity),
                            vColor.opacity(0.5 * discOpacity),
                            vColor.opacity(0.3 * discOpacity)
                        ],
                        center: .center,
                        startRadius: size * 0.06,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
                // Outer rim
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                // Dense groove rings
                .overlay(
                    ForEach(0..<grooveCount, id: \.self) { i in
                        let t = CGFloat(i) / CGFloat(grooveCount - 1)
                        let ratio = innerRadius + t * (outerRadius - innerRadius)
                        let diameter = size * ratio
                        let opacity: Double = {
                            if i % 5 == 0 { return 0.08 }
                            if i % 3 == 0 { return 0.05 }
                            return 0.03
                        }()

                        Circle()
                            .stroke(Color.white.opacity(opacity), lineWidth: i % 5 == 0 ? 0.8 : 0.4)
                            .frame(width: diameter, height: diameter)
                    }
                )
                .rotationEffect(.degrees(vinylRotationAngle))

            // Light sheen — stays fixed, does NOT rotate
            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.02),
                    .clear,
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Circle())
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Radial Lyrics (matches TurntableView layout)

    private func radialLyrics(
        lyrics: [String],
        currentIndex: Double,
        centerX: CGFloat,
        centerY: CGFloat,
        startRadius: CGFloat
    ) -> some View {
        let textLeftEdge = centerX + startRadius
        let maxTextWidth = max(120, cardWidth - textLeftEdge - 12)
        let effectiveRadius = startRadius + maxTextWidth / 2

        let anchorAngle: Double = 90.0
        let minAngle: Double = 5.0
        let maxAngle: Double = 175.0
        let visualGap: CGFloat = 36

        let clampedIndex = min(max(0, currentIndex), Double(lyrics.count - 1))
        let intIndex = Int(floor(clampedIndex))
        let fraction = clampedIndex - Double(intIndex)

        // Each lyric is measured as one visual block. A wrapped lyric therefore
        // consumes more height internally, while the gap between neighbouring
        // block edges remains constant—matching TurntableView's radial layout.
        func blockHeight(at index: Int) -> CGFloat {
            let distance = abs(index - intIndex)
            let style = shareLyricStyle(distance)
            let renderedWeight = shareResolvedLyricWeight(style.weight)
            let lineCount = shareEstimatedLineCount(
                for: lyrics[index],
                fontSize: style.fontSize,
                weight: renderedWeight,
                maxWidth: maxTextWidth
            )
            let font = shareUIFont(size: style.fontSize, weight: renderedWeight)
            return CGFloat(lineCount) * font.lineHeight * style.scale
        }

        func angleDistance(between first: Int, and second: Int) -> Double {
            let centreDistance = blockHeight(at: first) / 2
                + visualGap
                + blockHeight(at: second) / 2
            return Double(centreDistance / effectiveRadius) * (180.0 / .pi)
        }

        var baseAngles = Array(repeating: 0.0, count: lyrics.count)
        if intIndex + 1 < lyrics.count {
            for index in (intIndex + 1)..<lyrics.count {
                baseAngles[index] = baseAngles[index - 1]
                    + angleDistance(between: index - 1, and: index)
            }
        }
        if intIndex > 0 {
            for index in stride(from: intIndex - 1, through: 0, by: -1) {
                baseAngles[index] = baseAngles[index + 1]
                    - angleDistance(between: index, and: index + 1)
            }
        }

        let transitionDistance = intIndex + 1 < lyrics.count
            ? angleDistance(between: intIndex, and: intIndex + 1)
            : 0
        let scrollOffset = baseAngles[intIndex] - anchorAngle
            + fraction * transitionDistance

        return ZStack {
            ForEach(Array(lyrics.indices), id: \.self) { index in
                let angleDeg = baseAngles[index] - scrollOffset

                if angleDeg >= minAngle && angleDeg <= maxAngle {
                    let angleRad = angleDeg * .pi / 180.0
                    let x = centerX + effectiveRadius * sin(angleRad)
                    let y = centerY - effectiveRadius * cos(angleRad)
                    let textRotation = angleDeg - 90.0

                    let fractionalDist = abs(Double(index) - currentIndex)
                    let style = shareLyricStyleInterpolated(fractionalDist)
                    let renderedWeight = shareResolvedLyricWeight(style.weight)

                    Group {
                        if fractionalDist < 0.5 {
                            KaraokeLyricText(
                                text: lyrics[index],
                                fillProgress: 1,
                                fontSize: style.fontSize,
                                weight: renderedWeight,
                                filledColor: .black,
                                unfilledColor: Color.black.opacity(0.38),
                                maxWidth: maxTextWidth,
                                showsHandwrittenHighlight: true
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                        } else {
                            Text(lyrics[index])
                                .font(customization.fontDesign.font(size: style.fontSize, weight: renderedWeight))
                                .foregroundColor(customization.textColor.opacity(style.opacity))
                                .shadow(color: customization.textColor.opacity(0.15), radius: 6)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: maxTextWidth, alignment: .leading)
                        }
                    }
                        .blur(radius: style.blur)
                        .scaleEffect(style.scale, anchor: .leading)
                        .rotationEffect(.degrees(textRotation))
                        .position(x: x, y: y)
                }
            }
        }
    }

    /// Style for each lyric line by distance from current
    private func shareLyricStyle(_ distance: Int) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat, scale: CGFloat) {
        let base: (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat, scale: CGFloat)

        switch distance {
        case 0:  base = (30, 1.0,  .bold,     0,   1.0)
        case 1:  base = (24, 0.45, .semibold, 0.5, 0.92)
        case 2:  base = (22, 0.30, .medium,   1.0, 0.84)
        case 3:  base = (20, 0.20, .regular,  1.5, 0.76)
        case 4:  base = (18, 0.15, .regular,  2.2, 0.68)
        default: base = (18, 0.10, .regular,  3.0, 0.60)
        }

        return (base.fontSize * shareLyricFontScale, base.opacity, base.weight, base.blur, base.scale)
    }

    /// Interpolated radial style for smooth transitions
    private func shareLyricStyleInterpolated(_ fractionalDistance: Double) -> (fontSize: CGFloat, opacity: Double, weight: Font.Weight, blur: CGFloat, scale: CGFloat) {
        let d = abs(fractionalDistance)
        let lower = Int(floor(d))
        let upper = min(lower + 1, 6)
        let frac = CGFloat(d - Double(lower))

        let s0 = shareLyricStyle(lower)
        let s1 = shareLyricStyle(upper)

        return (
            fontSize: s0.fontSize + (s1.fontSize - s0.fontSize) * frac,
            opacity: s0.opacity + (s1.opacity - s0.opacity) * Double(frac),
            weight: frac < 0.5 ? s0.weight : s1.weight,
            blur: s0.blur + (s1.blur - s0.blur) * frac,
            scale: s0.scale + (s1.scale - s0.scale) * frac
        )
    }

    /// Applies the selected weight while preserving the visual hierarchy
    /// between current and older lyric lines. Bold is the default baseline.
    private func shareResolvedLyricWeight(_ baseWeight: Font.Weight) -> Font.Weight {
        let baseRank: Int
        switch baseWeight {
        case .heavy, .black: baseRank = 4
        case .bold: baseRank = 3
        case .semibold: baseRank = 2
        case .medium: baseRank = 1
        default: baseRank = 0
        }

        let selectedRank: Int
        switch customization.fontWeight {
        case .regular: selectedRank = 0
        case .medium: selectedRank = 1
        case .semibold: selectedRank = 2
        case .bold: selectedRank = 3
        case .heavy: selectedRank = 4
        }

        let resolvedRank = min(4, max(0, baseRank + selectedRank - 3))
        switch resolvedRank {
        case 4: return .heavy
        case 3: return .bold
        case 2: return .semibold
        case 1: return .medium
        default: return .regular
        }
    }

    private func shareUIFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .heavy, .black: return .heavy
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        default: return .regular
        }
    }

    private func shareUIFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        if let customName = customization.fontDesign.customFontName,
           let font = UIFont(name: customName, size: size) {
            return font
        }

        let font = UIFont.systemFont(ofSize: size, weight: shareUIFontWeight(weight))
        let design: UIFontDescriptor.SystemDesign?
        switch customization.fontDesign {
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        default: design = nil
        }

        guard let design,
              let descriptor = font.fontDescriptor.withDesign(design) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Measures the complete visual block, including automatic wrapping.
    private func shareEstimatedLineCount(
        for text: String,
        fontSize: CGFloat,
        weight: Font.Weight,
        maxWidth: CGFloat
    ) -> Int {
        let font = shareUIFont(size: fontSize, weight: weight)
        let size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let rect = (text as NSString).boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return max(1, Int(ceil(rect.height / font.lineHeight)))
    }

    // MARK: - Branding Footer

    private var brandingFooter: some View {
        HStack(spacing: 0) {
            Image(systemName: "record.circle")
                .font(.system(size: 12, weight: .semibold))
            Text(AppConstants.appName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Helper to create ShareCardData from Album

extension ShareCardData {
    init(album: Album, track: Track? = nil, lyrics: [String]? = nil, currentLyricIndex: Int? = nil, lyricLines: [LyricLine]? = nil, baseStyle: TurntableBaseStyle = .darkWalnut,
         playbackProgress: Double = 0, isPlaying: Bool = false,
         rpm: Double = AppConstants.rpm33, tonearmColor: Color = .gray,
         needleLifted: Bool = false, needleParked: Bool = false,
         lyricFillProgress: Double = 1, lyricMarkerProgress: Double = 1) {
        self.album = album
        self.playbackProgress = playbackProgress
        self.isPlaying = isPlaying
        self.rpm = rpm
        self.tonearmColor = tonearmColor
        self.needleLifted = needleLifted
        self.needleParked = needleParked
        self.lyricFillProgress = lyricFillProgress
        self.lyricMarkerProgress = lyricMarkerProgress
        self.albumTitle = album.title
        self.artist = album.artist
        self.trackTitle = track?.title
        self.accentColor = album.color
        self.year = album.releaseYear
        self.lyrics = lyrics
        self.currentLyricIndex = currentLyricIndex
        self.lyricLines = lyricLines
        self.baseStyle = baseStyle

        if let data = album.customCoverImageData {
            self.coverImage = UIImage(data: data)
        } else {
            self.coverImage = nil
        }
    }
}
