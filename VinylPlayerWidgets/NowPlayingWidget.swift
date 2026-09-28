 import AppIntents
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget Definitions

struct NowPlayingWidget: Widget {
    let kind = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider(style: .centered)) { entry in
            NowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackgroundView(entry: entry)
                }
        }
        .configurationDisplayName("Now Playing")
        .description("Centered turntable style.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowPlayingTiltedWidget: Widget {
    let kind = "NowPlayingTiltedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider(style: .radial)) { entry in
            NowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackgroundView(entry: entry)
                }
        }
        .configurationDisplayName("Radial Lyrics")
        .description("The full player's radial lyrics and turntable.")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct NowPlayingRippleWidget: Widget {
    let kind = "NowPlayingRippleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider(style: .ripple)) { entry in
            NowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackgroundView(entry: entry)
                }
        }
        .configurationDisplayName("Ripple Lyrics")
        .description("The full player's curved ripple lyrics and turntable.")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline Entry

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let trackTitle: String
    let artist: String
    let albumTitle: String
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let isPlaying: Bool
    let progress: Double
    let artworkImage: UIImage?
    let dominantColorHex: String?
    let currentLyric: String?
    let previousLyric: String?
    let nextLyric: String?
    let lyricContext: [String]?
    let currentLyricContextIndex: Int?
    let turntableStyle: WidgetTurntableStyle
    var baseStyle: TurntableBaseStyle = .darkWalnut

    var hasTrack: Bool { !trackTitle.isEmpty }
    var hasLyrics: Bool { currentLyric != nil && !(currentLyric?.isEmpty ?? true) }

    static let placeholder = NowPlayingEntry(
        date: Date(),
        trackTitle: "Speak Now",
        artist: "Taylor Swift",
        albumTitle: "Speak Now (TV)",
        duration: 225,
        elapsedTime: 83,
        isPlaying: true,
        progress: 0.37,
        artworkImage: nil,
        dominantColorHex: "#8B5A6B",
        currentLyric: "I was a dreamer before you went and let me down",
        previousLyric: "How you held me in your arms that September night",
        nextLyric: "Now it's October and we're far apart",
        lyricContext: [
            "Please don't be in love with someone else",
            "This night is sparkling, don't you let it go",
            "How you held me in your arms that September night",
            "I was a dreamer before you went and let me down",
            "Now it's October and we're far apart",
            "The lingering question kept me up",
            "Who do you love?"
        ],
        currentLyricContextIndex: 3,
        turntableStyle: .centered
    )

    static let empty = NowPlayingEntry(
        date: Date(),
        trackTitle: "",
        artist: "",
        albumTitle: "",
        duration: 0,
        elapsedTime: 0,
        isPlaying: false,
        progress: 0,
        artworkImage: nil,
        dominantColorHex: nil,
        currentLyric: nil,
        previousLyric: nil,
        nextLyric: nil,
        lyricContext: nil,
        currentLyricContextIndex: nil,
        turntableStyle: .centered
    )

    func styled(_ style: WidgetTurntableStyle) -> NowPlayingEntry {
        NowPlayingEntry(
            date: date,
            trackTitle: trackTitle,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            elapsedTime: elapsedTime,
            isPlaying: isPlaying,
            progress: progress,
            artworkImage: artworkImage,
            dominantColorHex: dominantColorHex,
            currentLyric: currentLyric,
            previousLyric: previousLyric,
            nextLyric: nextLyric,
            lyricContext: lyricContext,
            currentLyricContextIndex: currentLyricContextIndex,
            turntableStyle: style,
            baseStyle: baseStyle
        )
    }
}

// MARK: - Timeline Provider

struct NowPlayingTimelineProvider: TimelineProvider {
    let style: WidgetTurntableStyle

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: Date(),
            trackTitle: "Speak Now",
            artist: "Taylor Swift",
            albumTitle: "Speak Now (TV)",
            duration: 225,
            elapsedTime: 83,
            isPlaying: true,
            progress: 0.37,
            artworkImage: nil,
            dominantColorHex: "#8B5A6B",
            currentLyric: "I was a dreamer before you went and let me down",
            previousLyric: "How you held me in your arms that September night",
            nextLyric: "Now it's October and we're far apart",
            lyricContext: [
                "Please don't be in love with someone else",
                "This night is sparkling, don't you let it go",
                "How you held me in your arms that September night",
                "I was a dreamer before you went and let me down",
                "Now it's October and we're far apart",
                "The lingering question kept me up",
                "Who do you love?"
            ],
            currentLyricContextIndex: 3,
            turntableStyle: style
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        Task { @MainActor in
            WidgetPlaybackState.refresh()
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        Task { @MainActor in
            WidgetPlaybackState.refresh()
            let now = Date()
            guard let shared = loadSharedData(), shared.hasTrack else {
                completion(Timeline(entries: [currentEntry()], policy: .after(now.addingTimeInterval(300))))
                return
            }
            let dates = shared.lyricEntryDates(from: now)
            let artwork = shared.artworkData.flatMap { UIImage(data: $0) }
            let base = savedBaseStyle
            let entries = dates.map { entry(shared: shared.projected(at: $0), artwork: artwork, date: $0, base: base) }
            completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .after(now.addingTimeInterval(300))))
        }
    }

    private func loadSharedData() -> SharedNowPlayingData? {
        guard let data = UserDefaults(suiteName: AppConstants.appGroupId)?.data(forKey: SharedNowPlayingData.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(SharedNowPlayingData.self, from: data)
    }

    private var savedBaseStyle: TurntableBaseStyle {
        let raw = UserDefaults(suiteName: AppConstants.appGroupId)?
            .string(forKey: AppConstants.StorageKeys.turntableBaseStyle)
        return raw.flatMap(TurntableBaseStyle.init(rawValue:)) ?? .darkWalnut
    }

    private func currentEntry() -> NowPlayingEntry {
        guard let shared = loadSharedData(), shared.hasTrack else {
            return NowPlayingEntry(
                date: Date(), trackTitle: "", artist: "", albumTitle: "",
                duration: 0, elapsedTime: 0, isPlaying: false, progress: 0,
                artworkImage: nil, dominantColorHex: nil,
                currentLyric: nil, previousLyric: nil, nextLyric: nil,
                lyricContext: nil, currentLyricContextIndex: nil,
                turntableStyle: style, baseStyle: savedBaseStyle
            )
        }

        let now = Date()
        return entry(shared: shared.projected(at: now), artwork: shared.artworkData.flatMap { UIImage(data: $0) }, date: now, base: savedBaseStyle)
    }

    private func entry(shared: SharedNowPlayingData, artwork: UIImage?, date: Date, base: TurntableBaseStyle) -> NowPlayingEntry {
        return NowPlayingEntry(
            date: date,
            trackTitle: shared.trackTitle,
            artist: shared.artist,
            albumTitle: shared.albumTitle,
            duration: shared.duration,
            elapsedTime: shared.elapsedTime,
            isPlaying: shared.isPlaying,
            progress: shared.progress,
            artworkImage: artwork,
            dominantColorHex: shared.dominantColorHex,
            currentLyric: shared.currentLyric,
            previousLyric: shared.previousLyric,
            nextLyric: shared.nextLyric,
            lyricContext: shared.lyricContext,
            currentLyricContextIndex: shared.currentLyricContextIndex,
            turntableStyle: style, baseStyle: base
        )
    }
}

// MARK: - Background View

struct WidgetBackgroundView: View {
    let entry: NowPlayingEntry
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if entry.hasTrack {
            if let artworkImage = entry.artworkImage {
                WidgetImageGradient(image: artworkImage, count: 3)
            } else {
                // ImageGradient needs pixels to sample. Preserve its vertical
                // three-stop character when only the saved dominant colour is
                // available instead of falling back to a flat pale surface.
                let dominant = dominantColor
                LinearGradient(
                    colors: [
                        dominant.mix(with: .white, by: colorScheme == .dark ? 0.06 : 0.28),
                        dominant,
                        dominant.mix(with: .black, by: colorScheme == .dark ? 0.46 : 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            Color(white: colorScheme == .dark ? 0.12 : 0.93)
        }
    }

    private var dominantColor: Color {
        guard let hex = entry.dominantColorHex else {
            return Color(red: 0.55, green: 0.35, blue: 0.42)
        }
        return Color(hex: hex)
    }
}

/// Synchronous WidgetKit counterpart of ImageGradient. A widget snapshot
/// cannot rely on @State being populated after onAppear, so the same three
/// horizontal area-average samples are extracted before rendering the view.
private struct WidgetImageGradient: View {
    let colors: [Color]

    init(image: UIImage, count: Int) {
        colors = Self.extractColors(from: image, count: count)
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private static func extractColors(from image: UIImage, count: Int) -> [Color] {
        let sampleCount = max(1, count)
        let maxDimension: CGFloat = 200
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let downsized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let ciImage = CIImage(image: downsized) else { return [.gray] }
        let context = CIContext(options: [.cacheIntermediates: false])
        let tileHeight = ciImage.extent.height / CGFloat(sampleCount)

        return (0..<sampleCount).compactMap { index in
            let filter = CIFilter.areaAverage()
            filter.inputImage = ciImage
            filter.extent = CGRect(
                x: ciImage.extent.minX,
                y: ciImage.extent.minY + tileHeight * CGFloat(index),
                width: ciImage.extent.width,
                height: tileHeight
            )
            guard let output = filter.outputImage else { return nil }

            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(
                output,
                toBitmap: &bytes,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return Color(
                red: Double(bytes[0]) / 255,
                green: Double(bytes[1]) / 255,
                blue: Double(bytes[2]) / 255,
                opacity: Double(bytes[3]) / 255
            )
        }
    }
}

// MARK: - Entry View (Router)

struct NowPlayingWidgetEntryView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if entry.hasTrack {
                if entry.turntableStyle == .tilted || entry.turntableStyle == .radial {
                    FullPlayerLyricsWidgetView(
                        entry: entry,
                        family: family,
                        colorScheme: colorScheme,
                        mode: .radial
                    )
                } else if entry.turntableStyle == .ripple {
                    FullPlayerLyricsWidgetView(
                        entry: entry,
                        family: family,
                        colorScheme: colorScheme,
                        mode: .ripple
                    )
                } else {
                    switch family {
                    case .systemSmall:
                        SmallWidgetView(entry: entry, colorScheme: colorScheme)
                    case .systemMedium:
                        MediumWidgetView(entry: entry, colorScheme: colorScheme)
                            .padding(16)
                    case .systemLarge:
                        LargeWidgetView(entry: entry, colorScheme: colorScheme)
                            .padding(16)
                    default:
                        SmallWidgetView(entry: entry, colorScheme: colorScheme)
                    }
                }
            } else {
                NotPlayingView(family: family, colorScheme: colorScheme, style: entry.turntableStyle)
            }
        }
        .environment(\.widgetTurntableBaseStyle, entry.baseStyle)
    }
}

// MARK: - Color Helpers

struct WidgetColors {
    let usesLightForeground: Bool

    init(colorScheme: ColorScheme, entry: NowPlayingEntry? = nil) {
        usesLightForeground = entry.map {
            WidgetBackgroundContrast.usesLightForeground(for: $0, fallback: colorScheme)
        } ?? (colorScheme == .dark)
    }

    var primaryText: Color {
        usesLightForeground ? .white : Color(white: 0.12)
    }

    var secondaryText: Color {
        usesLightForeground ? .white.opacity(0.64) : .black.opacity(0.5)
    }

    var tertiaryText: Color {
        usesLightForeground ? .white.opacity(0.42) : .black.opacity(0.3)
    }

    var controlColor: Color {
        usesLightForeground ? .white : Color(white: 0.12)
    }

    var controlDimColor: Color {
        usesLightForeground ? .white.opacity(0.52) : .black.opacity(0.4)
    }

    var progressTrack: Color {
        usesLightForeground ? .white.opacity(0.16) : .black.opacity(0.08)
    }

    var progressFill: Color {
        usesLightForeground ? .white.opacity(0.72) : .black.opacity(0.55)
    }
}

private enum WidgetBackgroundContrast {
    static func usesLightForeground(for entry: NowPlayingEntry, fallback: ColorScheme) -> Bool {
        if let image = entry.artworkImage, let luminance = averageLuminance(of: image) {
            return luminance < 0.43
        }
        if let hex = entry.dominantColorHex, let luminance = luminance(ofHex: hex) {
            return luminance < 0.43
        }
        return fallback == .dark
    }

    private static func averageLuminance(of image: UIImage) -> Double? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }

        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.cacheIntermediates: false]).render(
            output,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return relativeLuminance(
            red: Double(bytes[0]) / 255,
            green: Double(bytes[1]) / 255,
            blue: Double(bytes[2]) / 255
        )
    }

    private static func luminance(ofHex hex: String) -> Double? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return relativeLuminance(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

// MARK: - Detailed Vinyl Disc (matches ShareCardView)

struct WidgetVinylDisc: View {
    let size: CGFloat
    let artworkImage: UIImage?

    private let grooveCount = 30 // slightly fewer than share card for widget perf

    var body: some View {
        ZStack {
            // Disc body with rich radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.14),
                            Color(white: 0.11),
                            Color(white: 0.08),
                            Color(white: 0.06),
                            Color(white: 0.04)
                        ],
                        center: .center,
                        startRadius: size * 0.06,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // Outer rim
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: size, height: size)

            // Dense groove rings
            ForEach(0..<grooveCount, id: \.self) { i in
                let t = CGFloat(i) / CGFloat(grooveCount - 1)
                let ratio = 0.18 + t * (0.95 - 0.18) // innerRadius...outerRadius
                let diameter = size * ratio
                let opacity: Double = i % 5 == 0 ? 0.07 : (i % 3 == 0 ? 0.045 : 0.025)
                let width: CGFloat = i % 5 == 0 ? 0.7 : 0.4

                Circle()
                    .stroke(Color.white.opacity(opacity), lineWidth: width)
                    .frame(width: diameter, height: diameter)
            }

            // Center label — album cover
            if let img = artworkImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size * 0.35, height: size * 0.35)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 2)
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.61, green: 0.42, blue: 0.48),
                                Color(red: 0.48, green: 0.29, blue: 0.36)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.175
                        )
                    )
                    .frame(width: size * 0.35, height: size * 0.35)
            }

            // Spindle hole
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.025, height: size * 0.025)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )

            // Light sheen (fixed, doesn't rotate)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.015),
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
    }
}

// MARK: - Detailed Turntable Base (matches ShareCardView)

struct WidgetTurntableBase: View {
    @Environment(\.widgetTurntableBaseStyle) private var baseStyle
    let baseSize: CGFloat
    let vinylSize: CGFloat
    let artworkImage: UIImage?
    let isPlaying: Bool
    let progress: Double

    var body: some View {
        let scale = vinylSize / 380
        let layout = TurntableHardwareLayout(recordDiameter: 380,
                                             baseReferenceSize: 380,
                                             showsLyrics: false)
        ZStack {
            TurntableInsetPanel(baseStyle: baseStyle)
                .frame(width: baseSize, height: baseSize)
                .clipShape(RoundedRectangle(cornerRadius: baseSize * 0.08))
            ZStack {
                TurntablePlatterView(recordDiameter: 380)
                WidgetVinylDisc(size: 380, artworkImage: artworkImage)
                TurntableTonearmView(layout: layout, progress: progress,
                    isLifted: .constant(!isPlaying), isParked: !isPlaying && progress == 0,
                    tonearmColor: Color(white: 0.12), onSeek: { _ in })
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 380, height: 380)
            .scaleEffect(scale)
            .frame(width: vinylSize, height: vinylSize)
            TurntableSelectorControls(isPlaying: isPlaying, rpm: 33.33,
                                      onTogglePlayback: {}, onToggleSpeed: {})
                .frame(width: 168, height: 48)
                .scaleEffect(scale * 0.65)
                .offset(x: -baseSize * 0.36, y: baseSize * 0.39)
        }
        .frame(width: baseSize, height: baseSize)
        .allowsHitTesting(false)
    }
}

// MARK: - Tilted Turntable (matches ShareCardView lyricsPlayer layout)

struct WidgetTiltedTurntable: View {
    @Environment(\.widgetTurntableBaseStyle) private var baseStyle
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let artworkImage: UIImage?
    let isPlaying: Bool
    let progress: Double

    var body: some View {
        let geometry = WidgetLyricsGeometry(size: CGSize(width: frameWidth, height: frameHeight))
        let diameter = geometry.vinylRadius * 2
        let scale = diameter / 380
        let layout = TurntableHardwareLayout(recordDiameter: 380,
            baseReferenceSize: 380 * 0.85 / 1.14, showsLyrics: true)
        ZStack {
            ZStack {
                TurntableBaseView(layout: layout, baseStyle: baseStyle, isPlaying: isPlaying)
                    // Enlarge only the plinth for both radial/ripple widget sizes.
                    .scaleEffect(1.4)
                TurntablePlatterView(recordDiameter: 380)
                WidgetVinylDisc(size: 380, artworkImage: artworkImage)
                TurntableTonearmView(layout: layout, progress: progress,
                    isLifted: .constant(!isPlaying), isParked: !isPlaying && progress == 0,
                    tonearmColor: Color(white: 0.12), onSeek: { _ in })
            }
            .frame(width: 380, height: 380)
            .scaleEffect(scale)
            .position(x: geometry.centerX, y: geometry.centerY)

            TurntableSelectorControls(isPlaying: isPlaying, rpm: 33.33,
                                      onTogglePlayback: {}, onToggleSpeed: {})
                .frame(width: 168, height: 48)
                .rotationEffect(.degrees(-45))
                .scaleEffect(0.75 * scale)
                .position(x: (24 / sqrt(2.0) - 9.6) * 0.75 * scale + diameter * 0.025,
                          y: geometry.centerY + diameter * 0.64)
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Progress Bar

struct WidgetProgressBar: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let colors: WidgetColors
    let timeFont: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.progressTrack).frame(height: 3)
                    Capsule().fill(colors.progressFill)
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)

            HStack {
                Text(formatTime(elapsedTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: timeFont, weight: .medium, design: .monospaced))
            .foregroundStyle(colors.secondaryText)
        }
    }
}

// MARK: - Playback Controls

struct WidgetPlaybackControls: View {
    let isPlaying: Bool
    let colors: WidgetColors
    let iconSize: CGFloat
    let playSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: min(spacing, 8)) {
            Button(intent: SkipPreviousIntent()) {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(colors.controlDimColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playSize))
                    .foregroundStyle(colors.controlColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(intent: SkipNextIntent()) {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(colors.controlDimColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }
}

// MARK: - Lyrics Display

struct WidgetLyricLine: View {
    let text: String
    let isCurrent: Bool
    let colors: WidgetColors

    var body: some View {
        Text(text)
            .font(.system(size: isCurrent ? 13 : 11, weight: isCurrent ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isCurrent ? colors.primaryText : colors.secondaryText.opacity(0.6))
            .lineLimit(1)
    }
}

/// Single current lyric line (for medium widget)
struct WidgetLyricsSingle: View {
    let entry: NowPlayingEntry
    let colors: WidgetColors

    var body: some View {
        if let lyric = entry.currentLyric, !lyric.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 7))
                    .foregroundStyle(colors.secondaryText.opacity(0.4))
                Text(lyric)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.primaryText.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }
}

/// Three-line lyrics context (for large widget)
struct WidgetLyricsContext: View {
    let entry: NowPlayingEntry
    let colors: WidgetColors

    var body: some View {
        if entry.hasLyrics {
            VStack(spacing: 3) {
                if let prev = entry.previousLyric, !prev.isEmpty {
                    WidgetLyricLine(text: prev, isCurrent: false, colors: colors)
                }
                WidgetLyricLine(text: entry.currentLyric ?? "", isCurrent: true, colors: colors)
                if let next = entry.nextLyric, !next.isEmpty {
                    WidgetLyricLine(text: next, isCurrent: false, colors: colors)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Full Player Lyrics Widgets

private enum FullPlayerWidgetLyricsMode {
    case radial
    case ripple
}

/// Uses the same visual grammar as the full player. Only the canvas scale and
/// the amount of surrounding lyric context change for WidgetKit's fixed sizes.
private struct FullPlayerLyricsWidgetView: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    let colorScheme: ColorScheme
    fileprivate let mode: FullPlayerWidgetLyricsMode

    private var colors: WidgetColors { WidgetColors(colorScheme: colorScheme, entry: entry) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WidgetTiltedTurntable(
                    frameWidth: geo.size.width,
                    frameHeight: geo.size.height,
                    artworkImage: entry.artworkImage,
                    isPlaying: entry.isPlaying,
                    progress: entry.progress
                )

                if entry.hasLyrics {
                    Group {
                        switch mode {
                        case .radial:
                            WidgetRadialLyricsLayer(entry: entry, family: family, canvasSize: geo.size)
                        case .ripple:
                            WidgetRippleLyricsLayer(entry: entry, family: family, canvasSize: geo.size)
                        }
                    }
                    .mask {
                        if family == .systemSmall {
                            // Reserve the lower area for metadata and the three controls.
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.34),
                                .init(color: .clear, location: 0.44)
                            ], startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.white
                        }
                    }
                }

                // Matches the full player's feathered controls backdrop while
                // leaving the dominant-colour background visible above it.
                LinearGradient(
                    colors: [
                        .clear,
                        colors.usesLightForeground
                            ? Color.black.opacity(0.12)
                            : Color.white.opacity(0.08),
                        colors.usesLightForeground
                            ? Color.black.opacity(0.46)
                            : Color.white.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                contentLayout
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private var contentLayout: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 4) {
                Spacer()

                trackMetadata(centered: true, compact: true)

                WidgetPlaybackControls(isPlaying: entry.isPlaying, colors: colors,
                    iconSize: 14, playSize: 28, spacing: 0)
            }
            .padding(10)

        case .systemMedium:
            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 10) {
                    Spacer(minLength: 100)

                    VStack(alignment: .leading, spacing: 5) {
                        trackMetadata(centered: false, compact: false)

                        WidgetProgressBar(
                            progress: entry.progress,
                            elapsedTime: entry.elapsedTime,
                            duration: entry.duration,
                            colors: colors,
                            timeFont: 8
                        )

                        WidgetPlaybackControls(
                            isPlaying: entry.isPlaying,
                            colors: colors,
                            iconSize: 13,
                            playSize: 28,
                            spacing: 22
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(12)

        default:
            VStack(spacing: 7) {
                Spacer()

                trackMetadata(centered: true, compact: false)

                WidgetPlaybackControls(
                    isPlaying: entry.isPlaying,
                    colors: colors,
                    iconSize: 18,
                    playSize: 42,
                    spacing: 34
                )

                WidgetProgressBar(
                    progress: entry.progress,
                    elapsedTime: entry.elapsedTime,
                    duration: entry.duration,
                    colors: colors,
                    timeFont: 9
                )
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func trackMetadata(centered: Bool, compact: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 2) {
            Text(entry.trackTitle)
                .font(.system(size: compact ? 12 : 15, weight: .semibold))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)

            Text(entry.artist)
                .font(.system(size: compact ? 9 : 11, weight: .medium))
                .foregroundStyle(colors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

private struct WidgetLyricsGeometry {
    let size: CGSize

    var vinylRadius: CGFloat { size.height * 0.31 }
    var centerX: CGFloat { -size.width * 0.02 }
    var centerY: CGFloat { size.height * 0.36 }
}

private extension NowPlayingEntry {
    var widgetLyricLines: [String] {
        if let lyricContext {
            if lyricContext.contains(where: { !$0.isEmpty }) {
                return lyricContext
            }
        }

        return [previousLyric, currentLyric, nextLyric]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    var widgetCurrentLyricIndex: Int {
        guard let currentLyric, !currentLyric.isEmpty else { return 0 }
        if let currentLyricContextIndex,
           widgetLyricLines.indices.contains(currentLyricContextIndex),
           widgetLyricLines[currentLyricContextIndex] == currentLyric {
            return currentLyricContextIndex
        }
        return widgetLyricLines.firstIndex(of: currentLyric) ?? 0
    }
}

/// Both lyric widgets use the player's renderers with static completed highlights.
private struct WidgetRadialLyricsLayer: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    let canvasSize: CGSize

    var body: some View {
        let geometry = WidgetLyricsGeometry(size: canvasSize)
        let scale: CGFloat = family == .systemSmall ? 11.0 / 26 : 20.0 / 26
        RadialLyricsLayer(
            lines: entry.widgetLyricLines,
            currentIndex: Double(entry.widgetCurrentLyricIndex),
            intraLineProgress: 1, markerIntraLineProgress: 1,
            vinylCenterX: geometry.centerX / scale,
            vinylCenterY: geometry.centerY / scale,
            vinylRadius: geometry.vinylRadius / scale,
            canvasWidth: canvasSize.width / scale,
            canvasHeight: canvasSize.height / scale
        )
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct WidgetRippleLyricsLayer: View {
    let entry: NowPlayingEntry
    let family: WidgetFamily
    let canvasSize: CGSize

    var body: some View {
        let geometry = WidgetLyricsGeometry(size: canvasSize)
        let scale: CGFloat = family == .systemSmall ? 11.0 / 26 : 20.0 / 26
        RippleLyricsLayer(
            lines: entry.widgetLyricLines,
            currentIndex: entry.widgetCurrentLyricIndex,
            intraLineProgress: 1, markerIntraLineProgress: 1,
            vinylCenterX: geometry.centerX / scale,
            vinylCenterY: geometry.centerY / scale,
            vinylRadius: geometry.vinylRadius / scale,
            screenWidth: canvasSize.width / scale
        )
        .frame(width: canvasSize.width / scale, height: canvasSize.height / scale)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: NowPlayingEntry
    let colorScheme: ColorScheme

    private var colors: WidgetColors { WidgetColors(colorScheme: colorScheme, entry: entry) }

    var body: some View {
        if entry.turntableStyle == .tilted {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    WidgetTiltedTurntable(
                        frameWidth: geo.size.width,
                        frameHeight: geo.size.height,
                        artworkImage: entry.artworkImage,
                        isPlaying: entry.isPlaying,
                        progress: entry.progress
                    )

                    // Bottom text overlay
                    VStack(spacing: 2) {
                        Text(entry.trackTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)
                        Text(entry.artist)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 10)

                }
            }
        } else {
            VStack(spacing: 4) {
                WidgetTurntableBase(
                    baseSize: 64,
                    vinylSize: 52,
                    artworkImage: entry.artworkImage,
                    isPlaying: entry.isPlaying,
                    progress: entry.progress
                )

                Text(entry.trackTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)

                WidgetPlaybackControls(isPlaying: entry.isPlaying, colors: colors,
                    iconSize: 14, playSize: 28, spacing: 0)
            }
            .padding(8)
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: NowPlayingEntry
    let colorScheme: ColorScheme

    private var colors: WidgetColors { WidgetColors(colorScheme: colorScheme, entry: entry) }

    var body: some View {
        if entry.turntableStyle == .tilted {
            GeometryReader { geo in
                ZStack {
                    WidgetTiltedTurntable(
                        frameWidth: geo.size.width,
                        frameHeight: geo.size.height,
                        artworkImage: entry.artworkImage,
                        isPlaying: entry.isPlaying,
                        progress: entry.progress
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.trackTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colors.primaryText)
                                .lineLimit(1)

                            Text("\(entry.artist) · \(entry.albumTitle)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(colors.secondaryText)
                                .lineLimit(1)
                        }

                        if entry.hasLyrics {
                            WidgetLyricsSingle(entry: entry, colors: colors)
                        }

                        WidgetProgressBar(
                            progress: entry.progress,
                            elapsedTime: entry.elapsedTime,
                            duration: entry.duration,
                            colors: colors,
                            timeFont: 8
                        )

                        WidgetPlaybackControls(
                            isPlaying: entry.isPlaying,
                            colors: colors,
                            iconSize: 14,
                            playSize: 28,
                            spacing: 24
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
                }
            }
        } else {
            HStack(spacing: 12) {
                WidgetTurntableBase(
                    baseSize: 118,
                    vinylSize: 94,
                    artworkImage: entry.artworkImage,
                    isPlaying: entry.isPlaying,
                    progress: entry.progress
                )
                .frame(width: 126, height: 126)

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.trackTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)

                        Text("\(entry.artist) · \(entry.albumTitle)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }

                    if entry.hasLyrics {
                        WidgetLyricsSingle(entry: entry, colors: colors)
                    }

                    WidgetProgressBar(
                        progress: entry.progress,
                        elapsedTime: entry.elapsedTime,
                        duration: entry.duration,
                        colors: colors,
                        timeFont: 8
                    )

                    WidgetPlaybackControls(
                        isPlaying: entry.isPlaying,
                        colors: colors,
                        iconSize: 14,
                        playSize: 28,
                        spacing: 24
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: NowPlayingEntry
    let colorScheme: ColorScheme

    private var colors: WidgetColors { WidgetColors(colorScheme: colorScheme, entry: entry) }

    var body: some View {
        if entry.turntableStyle == .tilted {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    WidgetTiltedTurntable(
                        frameWidth: geo.size.width,
                        frameHeight: geo.size.height,
                        artworkImage: entry.artworkImage,
                        isPlaying: entry.isPlaying,
                        progress: entry.progress
                    )

                    VStack(spacing: 6) {
                        VStack(spacing: 2) {
                            Text(entry.trackTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colors.primaryText)
                                .lineLimit(1)

                            Text("\(entry.artist) · \(entry.albumTitle)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(colors.secondaryText)
                                .lineLimit(1)
                        }

                        if entry.hasLyrics {
                            WidgetLyricsContext(entry: entry, colors: colors)
                        }

                        WidgetProgressBar(
                            progress: entry.progress,
                            elapsedTime: entry.elapsedTime,
                            duration: entry.duration,
                            colors: colors,
                            timeFont: 9
                        )
                        .padding(.horizontal, 24)

                        WidgetPlaybackControls(
                            isPlaying: entry.isPlaying,
                            colors: colors,
                            iconSize: 18,
                            playSize: 40,
                            spacing: 32
                        )
                    }
                    .padding(.bottom, 12)
                }
            }
        } else {
            VStack(spacing: 6) {
                WidgetTurntableBase(
                    baseSize: 144,
                    vinylSize: 120,
                    artworkImage: entry.artworkImage,
                    isPlaying: entry.isPlaying,
                    progress: entry.progress
                )
                .frame(height: 144)

                VStack(spacing: 2) {
                    Text(entry.trackTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)

                    Text("\(entry.artist) · \(entry.albumTitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                }

                if entry.hasLyrics {
                    WidgetLyricsContext(entry: entry, colors: colors)
                }

                WidgetProgressBar(
                    progress: entry.progress,
                    elapsedTime: entry.elapsedTime,
                    duration: entry.duration,
                    colors: colors,
                    timeFont: 9
                )
                .padding(.horizontal, 24)

                WidgetPlaybackControls(
                    isPlaying: entry.isPlaying,
                    colors: colors,
                    iconSize: 18,
                    playSize: 40,
                    spacing: 32
                )
            }
            .padding(12)
        }
    }
}

// MARK: - Not Playing View

struct NotPlayingView: View {
    let family: WidgetFamily
    let colorScheme: ColorScheme
    let style: WidgetTurntableStyle

    private var colors: WidgetColors { WidgetColors(colorScheme: colorScheme) }

    private var baseSize: CGFloat {
        switch family {
        case .systemSmall: return 88
        case .systemMedium: return 112
        default: return 144
        }
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                verticalLayout
            }
        }
    }

    // MARK: - Medium (HStack)

    @ViewBuilder
    private var mediumLayout: some View {
        if style == .tilted || style == .radial || style == .ripple {
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    tiltedEmptyTurntable(frameWidth: geo.size.width, frameHeight: geo.size.height)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.primaryText)

                        Text("Tap to choose an album")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(colors.tertiaryText)
                    }
                    .padding(16)
                }
            }
        } else {
            HStack(spacing: 12) {
                emptyTurntable
                    .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Not Playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.primaryText)

                    Text("Tap to choose an album")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    // MARK: - Small / Large (VStack)

    @ViewBuilder
    private var verticalLayout: some View {
        if style == .tilted || style == .radial || style == .ripple {
            ZStack(alignment: .bottom) {
                GeometryReader { geo in
                    tiltedEmptyTurntable(frameWidth: geo.size.width, frameHeight: geo.size.height)
                }

                VStack(spacing: 2) {
                    Text("Not Playing")
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .medium))
                        .foregroundStyle(colors.secondaryText)

                    if family != .systemSmall {
                        Text("Tap to choose an album")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(colors.tertiaryText)
                    }
                }
                .padding(.bottom, 12)
            }
        } else {
            VStack(spacing: 8) {
                emptyTurntable

                Text("Not Playing")
                    .font(.system(size: family == .systemSmall ? 11 : 13, weight: .medium))
                    .foregroundStyle(colors.secondaryText)

                if family != .systemSmall {
                    Text("Tap to choose an album")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
        }
    }

    // MARK: - Empty Turntable (centered)

    private var emptyTurntable: some View {
        WidgetTurntableBase(baseSize: baseSize, vinylSize: baseSize * 0.8,
                            artworkImage: nil, isPlaying: false, progress: 0)
    }

    private func tiltedEmptyTurntable(frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        WidgetTiltedTurntable(frameWidth: frameWidth, frameHeight: frameHeight,
                             artworkImage: nil, isPlaying: false, progress: 0)
    }

}

// MARK: - Helpers

private func formatTime(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Previews

#Preview("Small — Centered", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry.placeholder
    NowPlayingEntry.empty
}

#Preview("Medium — Centered", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry.placeholder
}

#Preview("Large — Centered", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry.placeholder
}

#Preview("Small — Radial Lyrics", as: .systemSmall) {
    NowPlayingTiltedWidget()
} timeline: {
    NowPlayingEntry.placeholder.styled(.radial)
}

#Preview("Large — Radial Lyrics", as: .systemLarge) {
    NowPlayingTiltedWidget()
} timeline: {
    NowPlayingEntry.placeholder.styled(.radial)
}

#Preview("Small — Ripple Lyrics", as: .systemSmall) {
    NowPlayingRippleWidget()
} timeline: {
    NowPlayingEntry.placeholder.styled(.ripple)
}

#Preview("Large — Ripple Lyrics", as: .systemLarge) {
    NowPlayingRippleWidget()
} timeline: {
    NowPlayingEntry.placeholder.styled(.ripple)
}

private struct WidgetTurntableBaseStyleKey: EnvironmentKey {
    static let defaultValue: TurntableBaseStyle = .darkWalnut
}

private extension EnvironmentValues {
    var widgetTurntableBaseStyle: TurntableBaseStyle {
        get { self[WidgetTurntableBaseStyleKey.self] }
        set { self[WidgetTurntableBaseStyleKey.self] = newValue }
    }
}
