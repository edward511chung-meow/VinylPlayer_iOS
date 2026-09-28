import SwiftUI

/// A waveform-style seekable progress bar. Bars are generated deterministically
/// from the track ID so the same song always shows the same static shape.
struct WaveformProgressBar: View {
    @EnvironmentObject var styleManager: StyleManager

    /// 0…1 playback progress (or seek preview)
    let progress: Double
    /// Current time string (left label)
    let currentTime: String
    /// Total duration string (right label)
    let totalTime: String
    /// Stable seed so the waveform stays consistent per track
    let trackSeed: Int
    /// Whether the bar is disabled (no track loaded)
    var isDisabled: Bool = false
    /// Called with a 0…1 value while dragging
    var onSeekChanged: ((Double) -> Void)?
    /// Called when the drag ends
    var onSeekEnded: (() -> Void)?

    // MARK: - Config

    private let barCount = 80
    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 32

    // MARK: - Waveform Data

    /// Deterministic pseudo-random waveform heights (0…1) seeded by trackSeed.
    private var waveformSamples: [Double] {
        var seed = UInt64(abs(trackSeed) &+ 0x9E3779B9)
        var samples: [Double] = []
        for _ in 0..<barCount {
            // xorshift64
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            let raw = Double(seed % 1000) / 1000.0
            // Shape it: boost mids, add envelope
            let shaped = 0.15 + raw * 0.85
            samples.append(shaped)
        }
        // Apply a gentle envelope so edges taper
        for i in 0..<samples.count {
            let pos = Double(i) / Double(samples.count - 1)
            let envelope = sin(pos * .pi) * 0.4 + 0.6 // 0.6…1.0…0.6
            samples[i] *= envelope
        }
        return samples
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let samples = waveformSamples
                let totalSpacing = barSpacing * CGFloat(barCount - 1)
                let barWidth = max(1.5, (geo.size.width - totalSpacing) / CGFloat(barCount))
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(0..<barCount, id: \.self) { i in
                            let sample = samples[i]
                            let height = minBarHeight + CGFloat(sample) * (maxBarHeight - minBarHeight)
                            let isPlayed = Double(i) / Double(barCount) <= progress

                            WaveformBar(
                                width: barWidth,
                                height: isDisabled ? minBarHeight + CGFloat(sample) * 4 : height,
                                isPlayed: isPlayed,
                                accentColor: isDisabled ? .secondary.opacity(0.3) : .primary,
                                surfaceColor: isDisabled ? .secondary.opacity(0.15) : .secondary.opacity(0.3)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: maxBarHeight)
                .contentShape(Rectangle())
                .gesture(
                    isDisabled ? nil :
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newProgress = max(0, min(1, value.location.x / geo.size.width))
                            HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                            onSeekChanged?(newProgress)
                        }
                        .onEnded { _ in
                            onSeekEnded?()
                        }
                )
            }
            .frame(height: maxBarHeight)

            // Time labels
            HStack {
                Text(currentTime)
                Spacer()
                Text(totalTime)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Individual Bar

/// A static waveform bar. Playback only changes its played/unplayed colour.
private struct WaveformBar: View {
    let width: CGFloat
    let height: CGFloat
    let isPlayed: Bool
    let accentColor: Color
    let surfaceColor: Color

    private var barOpacity: Double {
        isPlayed ? 0.8 : 0.35
    }

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(isPlayed ? accentColor : surfaceColor)
            .frame(width: width, height: height)
            .opacity(barOpacity)
    }
}
