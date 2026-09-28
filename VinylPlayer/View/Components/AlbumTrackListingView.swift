import SwiftUI

/// iPod Nano-style track listing view used in CoverFlow flip.
struct AlbumTrackListingView: View {
    let album: Album
    var showsHeader = true
    @EnvironmentObject private var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager

    private var tracks: [Track] {
        album.sortedTracks
    }

    @State private var dominantColor: Color?

    private var headerColor: Color {
        dominantColor ?? album.color
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header (dominant color background)
            if showsHeader { header }

            // MARK: - Track list
            trackList
        }
        .background(Color(.systemGroupedBackground))
        .task {
            if showsHeader { await loadDominantColor() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(album.artist)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [headerColor, headerColor.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Track List

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        collectionVM.play(album: album, track: track)
                    } label: {
                        trackRow(track: track, index: index)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func trackRow(track: Track, index: Int) -> some View {
        HStack(spacing: 0) {
            // Track number
            Text("\(track.trackNumber)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, 8)

            // Track title
            Text(track.title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Duration
            Text(track.duration.formattedDuration)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground))
    }

    // MARK: - Dominant Color

    private func loadDominantColor() async {
        if let data = album.customCoverImageData {
            dominantColor = DominantColorExtractor.dominantColor(from: data)
        } else if let urlString = album.displayArtworkURL,
                  let url = URL(string: urlString) {
            dominantColor = await DominantColorExtractor.dominantColor(from: url)
        }
    }
}
