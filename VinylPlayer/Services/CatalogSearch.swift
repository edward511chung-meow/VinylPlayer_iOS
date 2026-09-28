import Foundation
import MusicKit
import Combine

struct CatalogSearchResult {
    var albums: [Album] = []
    // Song results own an album so the existing queue can retain their metadata.
    var songAlbums: [Album] = []
    var artists: [String] = []
    var isEmpty: Bool { albums.isEmpty && songAlbums.isEmpty && artists.isEmpty }
}

enum AppleCatalogSearch {
    static func search(_ query: String) async throws -> CatalogSearchResult {
        guard MusicAuthorization.currentStatus == .authorized else { throw MusicServiceError.notAuthorized }
        var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Album.self, Song.self, Artist.self])
        request.limit = 12
        let response = try await request.response()
        try Task.checkCancellation()
        let albums = response.albums.map {
            Album(title: $0.title, artist: $0.artistName,
                  releaseYear: $0.releaseDate.map { Calendar.current.component(.year, from: $0) },
                  genre: $0.genreNames.first, appleMusicId: $0.id.rawValue,
                  artworkURL: $0.artwork?.url(width: 600, height: 600)?.absoluteString)
        }
        let songs = response.songs.map { song in
            let track = Track(title: song.title, artist: song.artistName, albumTitle: song.albumTitle ?? song.title,
                              duration: song.duration ?? 0, trackNumber: song.trackNumber ?? 1,
                              appleMusicId: song.id.rawValue)
            return Album(title: song.albumTitle ?? song.title, artist: song.artistName, tracks: [track],
                         artworkURL: song.artwork?.url(width: 600, height: 600)?.absoluteString)
        }
        return CatalogSearchResult(albums: albums, songAlbums: songs, artists: response.artists.map(\.name))
    }

    static func tracks(for album: Album) async throws -> [Track] {
        guard let id = album.appleMusicId else { return album.tracks }
        let request = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(id))
        guard let item = try await request.response().items.first else { throw MusicServiceError.trackNotAvailable }
        let detailed = try await item.with([.tracks])
        return (detailed.tracks ?? []).map { song in
            Track(title: song.title, artist: song.artistName, albumTitle: album.title, duration: song.duration ?? 0,
                  trackNumber: song.trackNumber ?? 1, discNumber: song.discNumber ?? 1, appleMusicId: song.id.rawValue)
        }
    }
}

/// Each view owns its request, so discovery and search never overwrite one another.
@MainActor
final class CatalogSearchModel: ObservableObject {
    @Published var result = CatalogSearchResult()
    @Published var isLoading = false
    @Published var error: String?
    private var generation = UUID()

    func search(_ query: String, source: MusicSource, manager: MusicServiceManager) async {
        let request = UUID()
        generation = request
        result = CatalogSearchResult(); error = nil
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { isLoading = false; return }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            try await Task.sleep(for: .milliseconds(350))
            let value = try await manager.searchCatalog(query: term, source: source)
            try Task.checkCancellation()
            guard generation == request else { return }
            result = value
        } catch is CancellationError {} catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

struct SpotifyUnifiedSearch: Decodable {
    struct Page<T: Decodable>: Decodable { let items: [T] }
    struct SongItem: Decodable {
        let name: String; let artists: [SpotifyArtistSimple]; let album: SpotifyAlbum
        let duration_ms: Int; let track_number: Int; let disc_number: Int; let uri: String
    }
    let albums: Page<SpotifyAlbum>
    let tracks: Page<SongItem>
    let artists: Page<SpotifyArtistSimple>
}
struct SpotifyAlbumTrackPage: Decodable { let items: [SpotifyTrackItem]; let next: String? }
