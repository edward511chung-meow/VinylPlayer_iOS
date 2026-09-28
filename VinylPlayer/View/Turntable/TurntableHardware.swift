import SwiftUI

/// Two mechanical selectors, with the indicator driven by the player state.
struct TurntableSelectorControls: View {
    let isPlaying: Bool
    let rpm: Double
    let onTogglePlayback: () -> Void
    let onToggleSpeed: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            selector(upper: "45", lower: "33", lowerSelected: rpm < 40,
                     label: "唱片轉速", value: rpm < 40 ? "33 RPM" : "45 RPM",
                     action: onToggleSpeed)
            selector(upper: "STOP", lower: "START", lowerSelected: isPlaying,
                     label: isPlaying ? "暫停" : "播放", value: isPlaying ? "START" : "STOP",
                     action: onTogglePlayback)
        }
    }

    private func selector(upper: String, lower: String, lowerSelected: Bool,
                          label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                VStack(alignment: .trailing, spacing: 15) {
                    Text(upper + "·")
                    Text(lower + "·")
                }
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color(white: 0.86))
                .shadow(color: .black.opacity(0.65), radius: 1, y: 1)
                .frame(width: 29, alignment: .trailing)

                ZStack {
                    Circle().fill(.black.gradient)
                        .shadow(color: .black.opacity(0.65), radius: 2, x: 1, y: 3)
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.65), .black, .gray],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                    Circle().inset(by: 4).fill(Color(white: 0.025))
                    Circle().inset(by: 4).stroke(
                        LinearGradient(colors: [.white, Color(white: 0.35), .white.opacity(0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    Rectangle().fill(Color(white: 0.9))
                        .frame(width: 10, height: 1.5)
                        .offset(x: -15)
                        .rotationEffect(.degrees(lowerSelected ? -18 : 18))
                        .animation(.easeInOut(duration: 0.2), value: lowerSelected)
                }
                .frame(width: 48, height: 48)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// Full Player 與抽碟過場共用；安裝點及臂長只需在這裡調整。
struct TurntableHardwareLayout {
    let recordDiameter: CGFloat
    let baseReferenceSize: CGFloat
    let showsLyrics: Bool

    var tonearmSize: CGFloat { recordDiameter * 0.90 }
    var armLength: CGFloat { tonearmSize * 0.72 }
    var baseSideLength: CGFloat { baseReferenceSize * (showsLyrics ? 1.24 : 1.12) }
    var tonearmPivot: CGSize {
        CGSize(
            width: baseReferenceSize * (showsLyrics ? 0.05 : 0.006),
            height: -baseReferenceSize * (showsLyrics ? 0.64 : 0.625)
        )
    }
}

/// Continuous faceplate behind both the hardware and playback controls.
struct TurntableInsetPanel: View {
    let baseStyle: TurntableBaseStyle

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: baseStyle.gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if baseStyle.showsWoodGrain {
                    WoodGrainCanvas(size: max(geometry.size.width, geometry.size.height),
                                    style: baseStyle)
                }
                LinearGradient(colors: [.black.opacity(0.14), .clear, .black.opacity(0.08)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

struct TurntableBaseView: View {
    let layout: TurntableHardwareLayout
    let baseStyle: TurntableBaseStyle
    let isPlaying: Bool

    var body: some View {
        let sideLength = layout.baseSideLength
        let cornerRadius: CGFloat = 24
        let edgeOpacity = baseStyle.edgeHighlightOpacity

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: baseStyle.gradientColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: sideLength, height: sideLength)
                .shadow(color: .black.opacity(baseStyle.shadowOpacity), radius: 14, y: 6)

            if baseStyle.showsWoodGrain {
                WoodGrainCanvas(size: sideLength, style: baseStyle)
                    .frame(width: sideLength, height: sideLength)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(LinearGradient(colors: [Color.white.opacity(edgeOpacity.top),
                                                Color.white.opacity(edgeOpacity.bottom)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .frame(width: sideLength, height: sideLength)

            Circle()
                .fill(isPlaying ? Color(red: 0.2, green: 0.9, blue: 0.3) : Color(white: 0.18))
                .frame(width: 8, height: 8)
                .shadow(color: isPlaying ? Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.7) : .clear,
                        radius: 8)
                .offset(x: sideLength * 0.35, y: 0)
                .animation(.spring(duration: 0.3), value: isPlaying)
        }
        .rotationEffect(.degrees(45))
        .animation(.spring(duration: 0.4), value: baseStyle)
    }
}

struct TurntablePlatterView: View {
    let recordDiameter: CGFloat
    var showsTransparentRecord: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(white: colorScheme == .dark ? 0.20 : 0.74),
                             Color(white: colorScheme == .dark ? 0.09 : 0.48),
                             Color(white: colorScheme == .dark ? 0.03 : 0.22)],
                    center: .center, startRadius: recordDiameter * 0.36, endRadius: recordDiameter * 0.54))
                .overlay {
                    Circle().stroke(AngularGradient(
                        colors: [Color.white.opacity(0.55), Color.black.opacity(0.50),
                                 Color.white.opacity(0.16), Color.black.opacity(0.62), Color.white.opacity(0.55)],
                        center: .center), lineWidth: 2)
                }

            Circle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.72 : 0.46))
                .frame(width: recordDiameter + 9, height: recordDiameter + 9)

            if showsTransparentRecord {
                // A brushed silver mat gives the tinted record something
                // lighter to transmit while retaining the existing outer rim.
                Circle()
                    .fill(AngularGradient(
                        colors: [Color(white: 0.48), Color(white: 0.76), Color(white: 0.52),
                                 Color(white: 0.67), Color(white: 0.48)], center: .center))
                    .frame(width: recordDiameter - 2, height: recordDiameter - 2)
            }

            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.07), lineWidth: 0.45)
                    .frame(width: (recordDiameter + 9) * (0.20 + CGFloat(i) * 0.125),
                           height: (recordDiameter + 9) * (0.20 + CGFloat(i) * 0.125))
            }
        }
        .frame(width: recordDiameter + 16, height: recordDiameter + 16)
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
    }
}

struct TurntableTonearmView: View {
    let layout: TurntableHardwareLayout
    let progress: Double
    @Binding var isLifted: Bool
    let isParked: Bool
    let tonearmColor: Color
    var onSeek: (Double) -> Void

    var body: some View {
        InteractiveTonearmView(
            progress: progress,
            vinylCenterOffset: CGSize(width: -layout.tonearmPivot.width, height: -layout.tonearmPivot.height),
            isLifted: $isLifted,
            isParked: isParked,
            tonearmColor: tonearmColor,
            recordDiameter: layout.recordDiameter,
            hardwareSize: layout.tonearmSize,
            armLength: layout.armLength,
            onSeek: onSeek
        )
        .offset(layout.tonearmPivot)
    }
}
