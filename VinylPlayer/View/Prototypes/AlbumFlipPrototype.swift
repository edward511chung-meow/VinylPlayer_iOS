#if DEBUG
import SwiftUI

/// Standalone interaction study; does not read the library or start playback.
/// Reference: https://www.youtube.com/watch?v=Fr0K7pEsHeQ (Kavsoft).
/// Open the interactive Preview and tap any album, then Close/the backdrop.
struct AlbumFlipPrototype: View {
    // Tuning: normal duration, perspective and expanded size are kept here.
    private let duration = 0.45
    private let perspective: CGFloat = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: FlipDemoAlbum?
    @State private var progress: CGFloat = 0
    @State private var transitioning = false
    @State private var slowMotion = false

    var body: some View {
        GeometryReader { container in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Collection").font(.largeTitle.bold())
                    Toggle("Slow motion", isOn: $slowMotion)
                    Text("Tap an album to flip it open.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 24) {
                        ForEach(FlipDemoAlbum.samples) { album in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { open(album) } label: {
                                    FlipDemoCover(album: album)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .anchorPreference(key: FlipAlbumFrames.self, value: .bounds) { [album.id: $0] }
                                .opacity(selection?.id == album.id ? 0 : 1)
                                .accessibilityLabel("Open \(album.title)")
                                Text(album.title).font(.headline).lineLimit(1)
                                Text(album.artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollDisabled(selection != nil)
            .allowsHitTesting(selection == nil)
            .accessibilityHidden(selection != nil)
            .overlayPreferenceValue(FlipAlbumFrames.self) { frames in
                if let album = selection, let anchor = frames[album.id] {
                    let source = container[anchor]
                    let width = min(container.size.width - 32, 420)
                    let height = min(container.size.height - 32, 560)
                    let destination = CGRect(x: (container.size.width - width) / 2,
                                             y: (container.size.height - height) / 2,
                                             width: width, height: height)
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.28 * progress)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                        FlipDemoTransition(album: album, source: source, destination: destination,
                                           progress: progress, perspective: perspective,
                                           reduceMotion: reduceMotion, close: close)
                            .allowsHitTesting(!transitioning && progress == 1)
                    }
                    .frame(width: container.size.width, height: container.size.height)
                    .accessibilityAction(.escape) { close() }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var animation: Animation {
        .interpolatingSpring(duration: slowMotion ? 1.8 : duration, bounce: 0.1, initialVelocity: 0)
    }

    private func open(_ album: FlipDemoAlbum) {
        guard selection == nil, !transitioning else { return }
        transitioning = true
        selection = album
        // Mount the overlay at the source before animating its single progress value.
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? nil : animation, completionCriteria: .removed) {
                progress = 1
            } completion: {
                transitioning = false
            }
        }
    }

    private func close() {
        guard selection != nil, !transitioning else { return }
        transitioning = true
        withAnimation(reduceMotion ? nil : animation, completionCriteria: .removed) {
            progress = 0
        } completion: {
            selection = nil
            transitioning = false
        }
    }
}

/// Frame and face visibility use the SAME interpolated value. Switching faces
/// only when edge-on avoids mirrored text or a premature crossfade.
private struct FlipDemoTransition: View, Animatable {
    let album: FlipDemoAlbum
    let source: CGRect
    let destination: CGRect
    var progress: CGFloat
    let perspective: CGFloat
    let reduceMotion: Bool
    let close: () -> Void
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        AlbumFlipSurface(progress: progress, source: source, destination: destination,
                         reduceMotion: reduceMotion) {
            FlipDemoCover(album: album)
        } back: {
            FlipDemoDetails(album: album, close: close)
        }
    }
}

private struct FlipDemoDetails: View {
    let album: FlipDemoAlbum
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Album").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close album")
            }
            HStack(spacing: 16) {
                FlipDemoCover(album: album).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 8) {
                    Text(album.title).font(.title2.bold())
                    Text(album.artist).foregroundStyle(.secondary)
                    Text("2026 · 6 songs").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.offset) { index, title in
                        HStack(spacing: 16) {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 24)
                            Text(title).frame(maxWidth: .infinity, alignment: .leading)
                            Text("3:24").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        Divider()
                    }
                }
            }
        }
        .padding(24)
    }
}

private struct FlipDemoCover: View {
    let album: FlipDemoAlbum
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [album.color, album.color.opacity(0.65), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.22), lineWidth: geo.size.width * 0.1)
                    .padding(geo.size.width * 0.2)
                Image(systemName: "waveform")
                    .font(.system(size: geo.size.width * 0.2, weight: .ultraLight))
                VStack(alignment: .leading) {
                    Text(album.artist.uppercased()).font(.system(size: geo.size.width * 0.06, weight: .medium, design: .monospaced))
                    Spacer()
                    Text(album.title).font(.system(size: geo.size.width * 0.11, weight: .bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct FlipDemoAlbum: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let color: Color
    let tracks = ["First Light", "Side Streets", "Stay a Little", "After Hours", "Slow Motion", "Home Again"]
    static let samples: [Self] = [
        .init(id: 0, title: "Neon Skyline", artist: "Luna Echo", color: .indigo),
        .init(id: 1, title: "Autumn Letters", artist: "Willow & Pine", color: .orange),
        .init(id: 2, title: "Paper Moons", artist: "Mira Lane", color: .teal),
        .init(id: 3, title: "Analog Hearts", artist: "Circuit Theory", color: .pink),
        .init(id: 4, title: "Blue Hour", artist: "North Avenue", color: .blue),
        .init(id: 5, title: "Soft Focus", artist: "Sunday Club", color: .purple)
    ]
}

private struct FlipAlbumFrames: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#Preview("Album Flip — Interactive") {
    AlbumFlipPrototype()
}
#endif
