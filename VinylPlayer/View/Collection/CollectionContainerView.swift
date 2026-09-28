import SwiftUI
import SwiftData

/// Switches between grid and Cover Flow.
/// Landscape always uses CoverFlow with flip; portrait uses grid.
struct CollectionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager

    @Query private var allAlbums: [Album]
    @State private var activeIndex: Int?
    @State private var flipTrigger: Int = 0
    @State private var isFlipped: Bool = false
    @State private var flipAlbum: Album?
    @State private var flipSource: CGRect = .zero

    private let coverSize: CGFloat = 224

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeCoverFlow
            } else {
                GridCollectionView()
            }
        }
        .animation(.spring(duration: 0.3), value: verticalSizeClass == .compact)
        .fullScreenCover(item: $flipAlbum) { album in
            AlbumFlipPresentation(album: album, sourceFrame: flipSource, dismiss: { flipAlbum = nil }, keepsSourceFrame: true, sourceScale: 1.12, showsReflection: true) {
                AlbumTrackListingView(album: album, showsHeader: false)
            }
        }
    }

    // MARK: - Landscape CoverFlow

    private var landscapeCoverFlow: some View {
        let albums = allAlbums

        return GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    if albums.isEmpty {
                        emptyState
                    } else {
                        CoverFlow(config: .init(cardWidth: coverSize, activeElevation: -8), activeIndex: $activeIndex, flipTrigger: $flipTrigger, onFlipChanged: { flipped in
                            withAnimation(.spring(duration: 0.3)) {
                                isFlipped = flipped
                            }
                        }, onOpenAlbum: { index, frame in
                            guard albums.indices.contains(index) else { return }
                            flipSource = frame
                            updateAlbumFlipPresentation { flipAlbum = albums[index] }
                        }) {
                            ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                                AlbumCoverView(album: album, size: coverSize)
                                    .frame(width: coverSize, height: coverSize)
                                    .opacity(flipAlbum?.id == album.id ? 0 : 1)
                                    .shadow(
                                        color: .black.opacity(activeIndex == index ? 0.6 : 0.3),
                                        radius: activeIndex == index ? 24 : 8,
                                        x: 0,
                                        y: 12
                                    )
                            }
                        } backContent: { index in
                            if albums.indices.contains(index) {
                                let album = albums[index]
                                AlbumTrackListingView(album: album)
                                    .environmentObject(styleManager)
                            }
                        }
                        .frame(height: coverSize)
                        .zIndex(isFlipped ? 1 : 0)
                        .onAppear {
                            if let current = collectionVM.currentAlbum,
                               let idx = albums.firstIndex(of: current) {
                                activeIndex = idx
                            } else if activeIndex == nil {
                                activeIndex = 0
                            }
                        }

                    }

                    Spacer()

                    albumInfoLabel(albums: albums)
                        .padding(.bottom, 24)
                }

                // ⓘ Info button — bottom-right of the entire view
                if !albums.isEmpty, activeIndex != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                flipTrigger += 1
                            } label: {
                                ZStack {
                                    Image(systemName: "info.circle")
                                    if isFlipped {
                                        Rectangle()
                                            .frame(width: 2, height: 24)
                                            .rotationEffect(.degrees(-45))
                                    }
                                }
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Album Info Label

    private func albumInfoLabel(albums: [Album]) -> some View {
        let album = activeIndex.flatMap { albums.indices.contains($0) ? albums[$0] : nil }

        return VStack(spacing: 4) {
            Text(album?.title ?? "")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(album?.artist ?? "")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let year = album?.releaseYear {
                    Text("\(year)")
                }
                Text(L("collection.tracks_count", album?.tracks.count ?? 0))
            }
            .font(.system(size: 12))
            .foregroundColor(.gray.opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .frame(height: 72)
        .animation(.spring(duration: 0.2), value: activeIndex)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            VinylRecordIcon(size: 48)

            Text(L("collection.no_albums"))
                .font(.system(size: 16))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.5))
        }
    }
}
