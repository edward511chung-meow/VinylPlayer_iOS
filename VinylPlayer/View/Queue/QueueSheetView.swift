import SwiftUI
import SwiftData

struct QueueSheetView: View {
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSongs = false
    @State private var dominantColor: Color?

    private var queueBaseColor: Color {
        dominantColor ?? collectionVM.currentAlbum?.color ?? styleManager.theme.backgroundColor
    }

    private var artworkIdentity: String {
        guard let album = collectionVM.currentAlbum else { return "no-album" }
        return "\(album.id)-\(album.customCoverImageData?.count ?? 0)-\(album.displayArtworkURL ?? "")"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                queueBackground

                List {
                    if let track = collectionVM.currentTrack,
                       let album = collectionVM.currentAlbum {
                        Section {
                            queueRow(track: track, album: album, isNowPlaying: true)
                        } header: {
                            queueSectionTitle(L("queue.now_playing"))
                        }
                    }

                    if !collectionVM.playbackQueue.isEmpty {
                        Section {
                            ForEach(collectionVM.playbackQueue) { item in
                                Button { collectionVM.playQueueItem(item.id) } label: {
                                    queueRow(track: item.track, album: item.album)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        if let index = collectionVM.playbackQueue.firstIndex(where: { $0.id == item.id }) {
                                            collectionVM.removeFromQueue(at: index)
                                        }
                                    } label: { Label(L("queue.remove"), systemImage: "trash") }
                                }
                                .contextMenu {
                                    Button(L("queue.play_next"), systemImage: "text.line.first.and.arrowtriangle.forward") {
                                        if let index = collectionVM.playbackQueue.firstIndex(where: { $0.id == item.id }) {
                                            collectionVM.moveInQueue(from: IndexSet(integer: index), to: 0)
                                        }
                                    }
                                    Button(L("queue.remove"), systemImage: "trash", role: .destructive) {
                                        if let index = collectionVM.playbackQueue.firstIndex(where: { $0.id == item.id }) {
                                            collectionVM.removeFromQueue(at: index)
                                        }
                                    }
                                }
                            }
                            .onMove { source, destination in collectionVM.moveInQueue(from: source, to: destination) }
                        } header: { queueSectionTitle(L("queue.up_next")) }
                    } else {
                        Text(L("queue.empty")).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    if !collectionVM.playbackHistory.isEmpty {
                        Section {
                            ForEach(collectionVM.playbackHistory.reversed()) { item in
                                Button { collectionVM.playHistoryItem(item.id) } label: {
                                    queueRow(track: item.track, album: item.album)
                                }.buttonStyle(.plain)
                            }
                        } header: { queueSectionTitle(L("queue.history")) }
                    }
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                .listRowSpacing(0)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .environment(\.defaultMinListRowHeight, 124)
            }
            .navigationTitle(L("queue.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(L("queue.add_songs"), systemImage: "plus") { showAddSongs = true }
                        Button(L("queue.shuffle"), systemImage: "shuffle") { collectionVM.toggleShuffle() }
                        Button(L("queue.repeat") + ": " + collectionVM.repeatMode.rawValue, systemImage: collectionVM.repeatMode.iconName) { collectionVM.cycleRepeatMode() }
                        Button(L("queue.clear"), systemImage: "trash", role: .destructive) { collectionVM.clearQueue() }
                            .disabled(collectionVM.playbackQueue.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSongs) { QueueSongPicker() }
        .preferredColorScheme(.dark)
        .task(id: artworkIdentity) {
            await updateDominantColor()
        }
        .presentationDetents([.large])
        .presentationBackground(mutedBackgroundColor(queueBaseColor))
    }

    private var queueBackground: some View {
        ZStack {
            mutedBackgroundColor(queueBaseColor)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.gray.opacity(0.12),
                    Color.black.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.28)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: artworkIdentity)
    }

    private func queueSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
            .textCase(nil)
    }

    private func queueRow(
        track: Track,
        album: Album,
        isNowPlaying: Bool = false,
        showsReorderHandle: Bool = false
    ) -> some View {
        HStack(spacing: 24) {
            AlbumCoverView(album: album, size: 138)
                .clipShape(Rectangle())
                .rotationEffect(.degrees(artworkRotation(for: track.id)))
                .offset(x: -10)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    if isNowPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolEffect(
                                .variableColor.iterative,
                                isActive: collectionVM.isPlaying
                            )
                    }

                    Text(track.title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(2)
                        .handwrittenHighlight(isActive: isNowPlaying)
                }
                .foregroundStyle(isNowPlaying ? .black.opacity(0.78) : .white.opacity(0.95))

                Text(track.artist)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.trailing, 18)
                    .accessibilityHidden(true)
            }

        }
        .frame(minHeight: 124)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.6)
                .padding(.leading, 154)
        }
    }

    private func artworkRotation(for trackID: UUID) -> Double {
        let rotations = [-2.4, 1.8, -1.2, 2.2, -1.8, 1.1]
        let seed = trackID.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult &* 31 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        return rotations[seed % rotations.count]
    }

    private func mutedBackgroundColor(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            return color.opacity(0.82)
        }

        return Color(
            hue: Double(hue),
            saturation: Double(min(saturation * 0.48, 0.34)),
            brightness: Double(min(max(brightness * 0.74, 0.34), 0.58))
        )
    }

    private func updateDominantColor() async {
        guard let album = collectionVM.currentAlbum else {
            await MainActor.run { dominantColor = nil }
            return
        }

        let extractedColor: Color?
        if let data = album.customCoverImageData {
            extractedColor = DominantColorExtractor.dominantColor(from: data)
        } else if let urlString = album.displayArtworkURL,
                  let url = URL(string: urlString) {
            extractedColor = await DominantColorExtractor.dominantColor(from: url)
        } else {
            extractedColor = album.color
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.35)) {
                dominantColor = extractedColor ?? album.color
            }
        }
    }

}

private struct QueueSongPicker: View {
    @Query private var albums: [Album]
    @EnvironmentObject private var collectionVM: CollectionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var added = 0

    var body: some View {
        NavigationStack {
            List {
                ForEach(albums) { album in
                    let tracks = album.sortedTracks.filter {
                        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.artist.localizedCaseInsensitiveContains(search) || album.title.localizedCaseInsensitiveContains(search)
                    }
                    if !tracks.isEmpty {
                        Section {
                            ForEach(tracks) { track in
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        Button(L("queue.play_next")) { collectionVM.addToQueue(track: track, album: album, playNext: true); added += 1 }
                                        Button(L("queue.play_last")) { collectionVM.addToQueue(track: track, album: album); added += 1 }
                                    } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }
                                }
                            }
                        } header: {
                            HStack {
                                Text(album.title)
                                Spacer()
                                Menu {
                                    Button(L("queue.play_next")) { collectionVM.addAlbumToQueue(album, playNext: true); added += album.tracks.count }
                                    Button(L("queue.play_last")) { collectionVM.addAlbumToQueue(album); added += album.tracks.count }
                                } label: { Image(systemName: "plus") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(L("queue.add_songs"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
                ToolbarItem(placement: .bottomBar) { Text("\(added) " + L("queue.added")) }
            }
        }
    }
}
