import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity UI for the Now Playing experience.
/// Shows on Dynamic Island (compact, expanded, minimal) and Lock Screen.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            // MARK: - Lock Screen / StandBy Banner
            // DEBUG: Log that the widget view is being rendered
            let _ = print("[LiveActivity-Widget] Lock screen rendering — track: \(context.attributes.trackTitle), playing: \(context.state.isPlaying)")
            lockScreenView(context: context)

        } dynamicIsland: { context in
            let _ = print("[LiveActivity-Widget] Dynamic Island rendering — track: \(context.attributes.trackTitle)")
            return DynamicIsland {
                // MARK: - Expanded Region
                DynamicIslandExpandedRegion(.leading) {
                    artworkView(data: context.attributes.artworkData, size: 48)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.trackTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)

                        Text(context.attributes.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // Play/Pause indicator
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Progress bar
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .tint(.white)

                        HStack {
                            Text(formatTime(context.state.elapsedTime))
                            Spacer()
                            Text(formatTime(context.attributes.duration))
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }

            } compactLeading: {
                // MARK: - Compact Leading (left pill)
                artworkView(data: context.attributes.artworkData, size: 28)
                    .padding(.leading, 2)

            } compactTrailing: {
                // MARK: - Compact Trailing (right pill)
                HStack(spacing: 4) {
                    // Spinning vinyl indicator when playing
                    if context.state.isPlaying {
                        Image(systemName: "opticaldisc.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Mini progress ring
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 2)
                            .foregroundStyle(.tertiary)

                        Circle()
                            .trim(from: 0, to: context.state.progress)
                            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 16, height: 16)
                }
                .padding(.trailing, 2)

            } minimal: {
                // MARK: - Minimal (single small circle)
                ZStack {
                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<NowPlayingAttributes>) -> some View {
        HStack(spacing: 12) {
            // Album artwork
            artworkView(data: context.attributes.artworkData, size: 48)

            // Track info + progress
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.trackTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text("\(context.attributes.artist) · \(context.attributes.albumTitle)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Progress bar
                ProgressView(value: context.state.progress)
                    .tint(.white)
            }

            // Play state indicator
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.black.opacity(0.6))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func artworkView(data: Data?, size: CGFloat) -> some View {
        if let data = data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        } else {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
