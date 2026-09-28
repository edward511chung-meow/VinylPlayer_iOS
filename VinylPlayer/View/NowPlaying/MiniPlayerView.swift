import SwiftUI

/// Apple Music-style mini player bar above the tab bar.
/// Tap anywhere (except playback buttons) to expand to full-screen Now Playing.
/// Progress shown as a subtle background fill from left to right.
/// Supports iOS 26 liquid glass with fallback for older versions.
struct MiniPlayerView: View {
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager

    let onTap: () -> Void

    @State private var swipeOffset: CGFloat = 0
    // Track title lives above the artwork by default. During a horizontal swipe
    // it briefly sinks down + fades, so it visually passes behind the cover.
    // Range: 0 (at rest, above cover) → 1 (fully tucked under cover).
    @State private var titleSink: CGFloat = 0

    private var progress: Double { collectionVM.playbackProgress }

    var body: some View {
        ZStack {
            // Track title + artist — rendered FIRST so it sits behind the artwork
            // when we slide it downward during a horizontal swipe.
            VStack(alignment: .leading, spacing: 2) {
                Text(collectionVM.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(styleManager.theme.textPrimary)
                    .lineLimit(1)

                if let artist = collectionVM.currentTrack?.artist {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundColor(styleManager.theme.textSecondary)
                        .lineLimit(1)
                }
            }
            // Push the title to the leading edge and give it a real hit area so
            // taps land anywhere in the column, not just on the text glyphs.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: swipeOffset, y: titleSink * 64)
            .opacity(1 - titleSink)
            .allowsHitTesting(false)

            // Foreground row: artwork + spacer + controls. Only this layer
            // receives taps and drags.
            HStack(spacing: 12) {
                // Album artwork thumbnail
                if let album = collectionVM.currentAlbum {
                    AlbumCoverView(album: album, size: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(styleManager.theme.surfaceColor)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(styleManager.theme.textSecondary)
                                .font(.system(size: 16))
                        )
                }

                Spacer()

                // Play / Pause
                Button {
                    musicServiceManager.togglePlayback()
                } label: {
                    Image(systemName: collectionVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(collectionVM.currentTrack != nil ? styleManager.theme.textPrimary : styleManager.theme.textSecondary.opacity(0.4))
                        .frame(width: 40, height: 40)
                }
                .disabled(collectionVM.currentTrack == nil)

                // Next track
                Button {
                    collectionVM.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(collectionVM.currentTrack != nil ? styleManager.theme.textPrimary : styleManager.theme.textSecondary.opacity(0.4))
                        .frame(width: 36, height: 36)
                }
                .disabled(collectionVM.currentTrack == nil)
            }
            .contentShape(Rectangle())
            // Track title row uses .offset(...) above — keep its x motion in sync
            // so title and artwork never desync mid-swipe.
            .offset(x: swipeOffset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 64)
        .contentShape(Rectangle())
        .simultaneousGesture(
            // Larger minimum distance so a slow horizontal drag never eats a tap.
            // Apple's Music app uses ~20pt before a swipe steals the gesture.
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    guard isHorizontal else { return }
                    swipeOffset = value.translation.width * 0.4
                    // Fade + drop the title as the swipe ramps up. Clamp 0...1 so
                    // a very long swipe doesn't push the title past the cover.
                    titleSink = min(1, abs(value.translation.width) / 120)
                }
                .onEnded { value in
                    let threshold: CGFloat = 40
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    if isHorizontal, value.translation.width < -threshold, collectionVM.currentTrack != nil {
                        // Swipe left → next track
                        withAnimation(.easeOut(duration: 0.15)) {
                            swipeOffset = -200
                            titleSink = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            collectionVM.nextTrack()
                            swipeOffset = 200
                            titleSink = 0
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipeOffset = 0
                            }
                        }
                    } else if isHorizontal, value.translation.width > threshold, collectionVM.currentTrack != nil {
                        // Swipe right → previous track
                        withAnimation(.easeOut(duration: 0.15)) {
                            swipeOffset = 200
                            titleSink = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            collectionVM.previousTrack()
                            swipeOffset = -200
                            titleSink = 0
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipeOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            swipeOffset = 0
                            titleSink = 0
                        }
                    }
                }
        )
        .onTapGesture {
            onTap()
        }
        .modifier(LiquidGlassBackgroundModifier(
            cornerRadius: 16,
            progress: progress,
            accentColor: styleManager.theme.accentColor
        ))
    }
}

// MARK: - Liquid Glass Background

/// Applies iOS 26 liquid glass effect when available,
/// falls back to ultra-thin material for older versions.
/// Includes progress fill as a subtle tinted overlay.
struct LiquidGlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let progress: Double
    let accentColor: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(progressFill)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(.systemBackground).opacity(0.3))

                        progressFill
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Progress shown as subtle accent tint filling from left.
    private var progressFill: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: geo.size.width * progress)
                Spacer(minLength: 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.linear(duration: 0.3), value: progress)
    }
}
