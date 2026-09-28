import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \Album.title) private var albums: [Album]
    @Query(sort: \Track.title) private var tracks: [Track]
    @EnvironmentObject private var manager: MusicServiceManager
    @EnvironmentObject private var player: CollectionViewModel
    @StateObject private var catalog = CatalogSearchModel()
    @State private var query = ""
    @State private var source: MusicSource = .local
    @State private var retry = 0
    init(initialQuery: String = "") { _query = State(initialValue: initialQuery) }

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingTracks: [Track] { tracks.filter { "\($0.title) \($0.artist) \($0.albumTitle)".localizedStandardContains(term) } }
    private var matchingAlbums: [Album] { albums.filter { "\($0.title) \($0.artist)".localizedStandardContains(term) } }

    private var matchingArtists: [String] { Array(Set(tracks.map(\.artist))).filter { $0.localizedStandardContains(term) }.sorted() }

    var body: some View {
        NavigationStack {
            List {
                Picker(L("search.source"), selection: $source) {
                    Text(L("search.library")).tag(MusicSource.local)
                    Text("Apple Music").tag(MusicSource.appleMusic)
                    Text("Spotify").tag(MusicSource.spotify)
                }.pickerStyle(.segmented)
                if term.isEmpty {
                    ContentUnavailableView(L("search.start"), systemImage: "magnifyingglass", description: Text(L("library.search")))
                } else if source == .local {
                    if !matchingTracks.isEmpty {
                        Section(L("library.songs")) {
                            ForEach(matchingTracks.prefix(100)) { track in
                                LibraryTrackRow(track: track) { player.playTracks(matchingTracks, startingAt: track.id) }
                            }
                        }
                    }
                    if !matchingAlbums.isEmpty {
                        Section(L("search.albums")) {
                            ForEach(matchingAlbums.prefix(50)) { album in
                                NavigationLink { AlbumDetailView(album: album, albums: matchingAlbums) } label: { SearchAlbumLabel(album: album) }
                            }
                        }
                    }
                    if !matchingArtists.isEmpty {
                        Section(L("library.artists")) {
                            ForEach(matchingArtists, id: \.self) { artist in
                                NavigationLink { LibrarySongsView(title: artist, tracks: tracks.filter { $0.artist == artist }) } label: { Label(artist, systemImage: "music.mic") }
                            }
                        }
                    }
                    if matchingTracks.isEmpty && matchingAlbums.isEmpty && matchingArtists.isEmpty { ContentUnavailableView.search(text: term) }
                } else if !manager.isAuthorized(source) {
                    ContentUnavailableView(L("search.connect"), systemImage: "person.crop.circle.badge.exclamationmark", description: Text(L("search.connect_hint")))
                } else {
                    if catalog.isLoading { ProgressView(L("search.loading")) }
                    if let error = catalog.error {
                        Text(error).foregroundStyle(.secondary)
                        Button(L("common.retry")) { retry += 1 }
                    }
                    Section(L("library.songs")) {
                        ForEach(catalog.result.songAlbums) { album in
                            CatalogResultRow(album: album, source: source, isSong: true)
                        }
                    }
                    Section(L("search.albums")) {
                        ForEach(catalog.result.albums) { album in CatalogResultRow(album: album, source: source) }
                    }
                    Section(L("library.artists")) {
                        ForEach(Array(Set(catalog.result.artists)).sorted(), id: \.self) { artist in
                            Button { query = artist } label: { Label(artist, systemImage: "music.mic") }
                        }
                    }
                    if !catalog.isLoading && catalog.error == nil && catalog.result.isEmpty { ContentUnavailableView.search(text: term) }
                }
            }
            .safeAreaPadding(.bottom, 128)
            .navigationTitle(L("search.title"))
            .searchable(text: $query, prompt: L("library.search"))
            .task(id: "\(source.rawValue)|\(term)|\(retry)|\(manager.isAuthorized(source))") {
                if source != .local, manager.isAuthorized(source) {
                    await catalog.search(term, source: source, manager: manager)
                }
            }
        }
    }
}

struct SearchAlbumLabel: View {
    let album: Album
    var isSong = false
    var body: some View {
        HStack(spacing: 12) {
            AlbumCoverView(album: album, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(isSong ? album.tracks.first?.title ?? album.title : album.title).lineLimit(2)
                Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct CatalogResultRow: View {
    let album: Album
    let source: MusicSource
    var isSong = false
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var manager: MusicServiceManager
    @EnvironmentObject private var player: CollectionViewModel
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SearchAlbumLabel(album: album, isSong: isSong)
                Spacer(minLength: 8)
                if loading { ProgressView() }
                else {
                    Menu {
                        Button(L("search.add_play"), systemImage: "play.fill") { perform(.play) }
                        Button(L("search.add_queue"), systemImage: "text.badge.plus") { perform(.queue) }
                        Button(L("search.add_collection"), systemImage: "plus") { perform(.save) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("library.actions"))
                }
            }
            if let url = serviceURL {
                Link(source.displayName, destination: url).font(.caption)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var serviceURL: URL? {
        if source == .spotify {
            if let uri = album.tracks.first?.spotifyURI, isSong {
                return URL(string: uri.replacingOccurrences(of: "spotify:track:", with: "https://open.spotify.com/track/"))
            }
            return album.spotifyId.flatMap { URL(string: "https://open.spotify.com/album/\($0)") }
        }
        if let id = album.appleMusicId { return URL(string: "https://music.apple.com/album/\(id)") }
        return album.tracks.first?.appleMusicId.flatMap { URL(string: "https://music.apple.com/song/\($0)") }
    }

    private enum Action { case play, queue, save }
    private func perform(_ action: Action) {
        guard !loading else { return }
        loading = true; error = nil
        Task { @MainActor in
            defer { loading = false }
            do {
                try await manager.loadCatalogTracks(album, source: source)
                let selectedServiceID = album.tracks.first?.appleMusicId
                let selectedURI = album.tracks.first?.spotifyURI
                let existing = Album.findByServiceId(appleMusicId: album.appleMusicId, spotifyId: album.spotifyId, in: context)
                    ?? Album.findDuplicate(title: album.title, artist: album.artist, in: context)
                let saved: Album
                if let existing {
                    // Import independent Track instances: never steal a relationship from search results.
                    for track in album.sortedTracks where !existing.tracks.contains(where: { $0.appleMusicId != nil && $0.appleMusicId == track.appleMusicId || $0.spotifyURI != nil && $0.spotifyURI == track.spotifyURI || $0.title == track.title && $0.trackNumber == track.trackNumber }) {
                        existing.tracks.append(Track(title: track.title, artist: track.artist, albumTitle: track.albumTitle, duration: track.duration, trackNumber: track.trackNumber, discNumber: track.discNumber, appleMusicId: track.appleMusicId, spotifyURI: track.spotifyURI))
                    }
                    if existing.appleMusicId == nil { existing.appleMusicId = album.appleMusicId }
                    if existing.spotifyId == nil { existing.spotifyId = album.spotifyId }
                    saved = existing
                } else { context.insert(album); saved = album }
                try context.save()
                let song = saved.sortedTracks.first { selectedServiceID != nil && $0.appleMusicId == selectedServiceID || selectedURI != nil && $0.spotifyURI == selectedURI }
                switch action {
                case .play:
                    if isSong, let song { player.playTracks([song]) } else { player.play(album: saved) }
                case .queue:
                    if isSong, let song { player.addToQueue(track: song, album: saved) } else { player.addAlbumToQueue(saved) }
                case .save: ToastManager.shared.success(L("search.saved"))
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
