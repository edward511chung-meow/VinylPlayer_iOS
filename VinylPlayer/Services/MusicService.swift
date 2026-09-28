import Foundation
import Combine

// MARK: - Unified Music Service Protocol

/// All music backends (Apple Music, Spotify, local) conform to this protocol.
protocol MusicService: AnyObject {
    var source: MusicSource { get }
    var isAuthorized: Bool { get }
    var authStatusPublisher: AnyPublisher<MusicAuthStatus, Never> { get }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }

    // Auth
    func authorize() async throws
    func deauthorize()

    // Library
    func fetchLibraryAlbums() async throws -> [Album]
    func searchAlbums(query: String) async throws -> [Album]

    func searchCatalog(query: String) async throws -> CatalogSearchResult
    func loadTracks(for album: Album) async throws -> [Track]

    // Playback
    func play(track: Track, in album: Album) async throws
    func pause()
    func resume()
    func seek(to progress: Double)
    func skipToNext()
    func skipToPrevious()

    // Lyrics
    func fetchTimeSyncedLyrics(for track: Track) async throws -> [LyricLine]?
}

// Default implementations for optional capabilities
extension MusicService {
    func searchCatalog(query: String) async throws -> CatalogSearchResult {
        if source == .appleMusic { return try await AppleCatalogSearch.search(query) }
        return CatalogSearchResult(albums: try await searchAlbums(query: query))
    }
    func loadTracks(for album: Album) async throws -> [Track] {
        if source == .appleMusic { return try await AppleCatalogSearch.tracks(for: album) }
        return album.tracks
    }
    func fetchTimeSyncedLyrics(for track: Track) async throws -> [LyricLine]? { nil }
}

// MARK: - Supporting Types

enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case local = "local"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic: return L("source.apple_music")
        case .spotify: return L("source.spotify")
        case .local: return L("source.local")
        }
    }

    var iconName: String {
        switch self {
        case .appleMusic: return "apple.logo"
        case .spotify: return "waveform"
        case .local: return "internaldrive"
        }
    }
}

enum MusicAuthStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case error(String)

    static func == (lhs: MusicAuthStatus, rhs: MusicAuthStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notDetermined, .notDetermined),
             (.authorized, .authorized),
             (.denied, .denied),
             (.restricted, .restricted): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }
}

struct PlaybackState: Equatable {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var trackId: String?
    var queueEntryID: UUID? = nil
    var didFinish = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
