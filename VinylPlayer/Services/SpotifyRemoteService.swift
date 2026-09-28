// ⚠️ COMPILE REQUIREMENT: This file requires the SpotifyiOS SDK.
//
// ## How to add SpotifyiOS SDK (official, supports SPM):
// 1. Xcode → File → Add Package Dependencies
// 2. URL: https://github.com/spotify/ios-sdk
// 3. Add SpotifyiOS framework to your target
//
// ## How to activate:
// In `MusicServiceManager.init()`, change:
//   `services[.spotify] = SpotifyService()`
// to:
//   `services[.spotify] = SpotifyRemoteService()`
//
// ## What's different from SpotifyService:
// - Uses SPTAppRemote for direct IPC with Spotify app (no "active device" requirement)
// - Delegate-based state updates (no HTTP polling every 1s)
// - Lower latency playback control
// - Still uses Web API for library/search (SPTAppRemote doesn't support those)
//
// ## User requirements:
// - Spotify Premium subscription
// - Spotify app installed on device

#if canImport(SpotifyiOS)
import Foundation
import Combine
import UIKit
import CommonCrypto
import SpotifyiOS

final class SpotifyRemoteService: NSObject, MusicService {

    let source: MusicSource = .spotify

    // MARK: - State

    private let authStatusSubject = CurrentValueSubject<MusicAuthStatus, Never>(.notDetermined)
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    var isAuthorized: Bool { authStatusSubject.value.isAuthorized }

    var authStatusPublisher: AnyPublisher<MusicAuthStatus, Never> {
        authStatusSubject.eraseToAnyPublisher()
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    // MARK: - SPTAppRemote

    private lazy var configuration: SPTConfiguration = {
        let config = SPTConfiguration(
            clientID: APIConfig.Spotify.clientId,
            redirectURL: URL(string: APIConfig.Spotify.redirectURI)!
        )
        config.tokenSwapURL = nil      // Using PKCE, no server needed
        config.tokenRefreshURL = nil
        return config
    }()

    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        return remote
    }()

    /// Track whether we're waiting for a connection after auth.
    private var pendingPlayURI: String?

    // MARK: - Init

    override init() {
        super.init()
        loadStoredTokens()
    }

    // MARK: - Auth

    /// Authorize via SPTAppRemote — opens Spotify app for consent.
    func authorize() async throws {
        // SPTAppRemote auth: opens Spotify app, user grants access,
        // Spotify redirects back with an access token in the URL.
        await MainActor.run {
            // authorizeAndPlayURI("") triggers auth without auto-playing
            appRemote.authorizeAndPlayURI("")
        }
    }

    /// Handle the callback URL from Spotify app after auth.
    /// Call this from your SceneDelegate/AppDelegate URL handler.
    func handleCallback(url: URL) {
        let params = appRemote.authorizationParameters(from: url)

        if let token = params?[SPTAppRemoteAccessTokenKey] {
            accessToken = token
            appRemote.connectionParameters.accessToken = token
            storeTokens()
            authStatusSubject.send(.authorized)

            // Connect the app remote
            appRemote.connect()
        } else if let error = params?[SPTAppRemoteErrorDescriptionKey] {
            authStatusSubject.send(.error(error))
        }
    }

    func deauthorize() {
        appRemote.disconnect()
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        clearStoredTokens()
        authStatusSubject.send(.notDetermined)
    }

    /// Call when app becomes active — reconnect if we have a token.
    func reconnectIfNeeded() {
        if let token = accessToken, !appRemote.isConnected {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        }
    }

    /// Call when app resigns active — disconnect cleanly.
    func disconnectOnBackground() {
        if appRemote.isConnected {
            appRemote.disconnect()
        }
    }

    // MARK: - Library (via Web API — SPTAppRemote doesn't support library access)

    func fetchLibraryAlbums() async throws -> [Album] {
        let token = try validTokenSync()

        let url = URL(string: "https://api.spotify.com/v1/me/albums?limit=50")!
        let data: SpotifySavedAlbumsResponse = try await spotifyRequest(url: url, token: token)
        return data.items.map { convertAlbum($0.album) }
    }

    func searchCatalog(query: String) async throws -> CatalogSearchResult {
        let token = try validTokenSync()
        var url = URLComponents(string: "https://api.spotify.com/v1/search")!
        url.queryItems = [.init(name: "q", value: query), .init(name: "type", value: "album,track,artist"), .init(name: "limit", value: "10")]
        let data: SpotifyUnifiedSearch = try await spotifyRequest(url: url.url!, token: token)
        return CatalogSearchResult(albums: data.albums.items.map { convertAlbum($0) }, songAlbums: data.tracks.items.map { item in
            let track = Track(title: item.name, artist: item.artists.first?.name ?? "", albumTitle: item.album.name,
                              duration: Double(item.duration_ms) / 1000, trackNumber: item.track_number, discNumber: item.disc_number, spotifyURI: item.uri)
            return Album(title: item.album.name, artist: track.artist, tracks: [track], artworkURL: item.album.images.first?.url)
        }, artists: data.artists.items.map(\.name))
    }

    func loadTracks(for album: Album) async throws -> [Track] {
        guard let id = album.spotifyId else { return album.tracks }
        let token = try validTokenSync()
        var url: URL? = URL(string: "https://api.spotify.com/v1/albums/\(id)/tracks?limit=50")
        var tracks: [Track] = []
        while let next = url {
            try Task.checkCancellation()
            let page: SpotifyAlbumTrackPage = try await spotifyRequest(url: next, token: token)
            tracks += page.items.map { Track(title: $0.name, artist: $0.artists.first?.name ?? album.artist, albumTitle: album.title,
                                             duration: Double($0.durationMs) / 1000, trackNumber: $0.trackNumber, discNumber: $0.discNumber, spotifyURI: $0.uri) }
            url = page.next.flatMap(URL.init(string:))
        }
        return tracks
    }

    func searchAlbums(query: String) async throws -> [Album] {
        let token = try validTokenSync()

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "limit", value: "25")
        ]

        let data: SpotifySearchResponse = try await spotifyRequest(url: components.url!, token: token)
        return data.albums.items.map { convertAlbum($0) }
    }

    // MARK: - Playback (via SPTAppRemote — direct IPC with Spotify app)

    func play(track: Track, in album: Album) async throws {
        guard let spotifyURI = track.spotifyURI else {
            throw MusicServiceError.trackNotAvailable
        }

        guard appRemote.isConnected else {
            // Try to connect first, queue the play for after connection
            pendingPlayURI = spotifyURI
            reconnectIfNeeded()
            // Wait briefly for connection
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            guard appRemote.isConnected else {
                throw MusicServiceError.playbackFailed(
                    "Cannot connect to Spotify app. Make sure Spotify is installed and open."
                )
            }
            return
        }

        appRemote.playerAPI?.play(spotifyURI, callback: { _, error in
            if let error {
                print("[SpotifyRemote] Play error: \(error.localizedDescription)")
            }
        })

        // Subscribe to player state updates via delegate
        appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
            if let error {
                print("[SpotifyRemote] Subscribe error: \(error.localizedDescription)")
            }
        })
    }

    func pause() {
        appRemote.playerAPI?.pause({ _, error in
            if let error { print("[SpotifyRemote] Pause error: \(error)") }
        })
    }

    func resume() {
        appRemote.playerAPI?.resume({ _, error in
            if let error { print("[SpotifyRemote] Resume error: \(error)") }
        })
    }

    func seek(to progress: Double) {
        let currentState = playbackStateSubject.value
        let positionMs = Int(progress * currentState.duration * 1000)
        appRemote.playerAPI?.seek(toPosition: positionMs, callback: { _, error in
            if let error { print("[SpotifyRemote] Seek error: \(error)") }
        })
    }

    func skipToNext() {
        appRemote.playerAPI?.skip(toNext: { _, error in
            if let error { print("[SpotifyRemote] Skip next error: \(error)") }
        })
    }

    func skipToPrevious() {
        appRemote.playerAPI?.skip(toPrevious: { _, error in
            if let error { print("[SpotifyRemote] Skip previous error: \(error)") }
        })
    }

    // MARK: - Token Storage (simplified — SPTAppRemote manages its own token)

    private let tokenKey = "spotify_remote_access_token"

    private func storeTokens() {
        UserDefaults.standard.set(accessToken, forKey: tokenKey)
    }

    private func loadStoredTokens() {
        accessToken = UserDefaults.standard.string(forKey: tokenKey)
        if accessToken != nil {
            authStatusSubject.send(.authorized)
        }
    }

    private func clearStoredTokens() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private func validTokenSync() throws -> String {
        guard let token = accessToken else { throw MusicServiceError.notAuthorized }
        return token
    }

    // MARK: - Web API Helpers

    private func spotifyRequest<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 401 { throw APIError.unauthorized }
            throw APIError.httpError(statusCode: statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func convertAlbum(_ spotifyAlbum: SpotifyAlbum) -> Album {
        Album(
            title: spotifyAlbum.name,
            artist: spotifyAlbum.artists.first?.name ?? "Unknown",
            releaseYear: spotifyAlbum.releaseDate.flatMap { Int(String($0.prefix(4))) },
            genre: nil,
            colorHex: "#1A1A1A",
            spotifyId: spotifyAlbum.id,
            artworkURL: spotifyAlbum.images.first?.url
        )
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyRemoteService: SPTAppRemoteDelegate {

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        print("[SpotifyRemote] Connected to Spotify app")

        // Set ourselves as player delegate for state updates
        appRemote.playerAPI?.delegate = self

        // If we had a pending play request, execute it now
        if let uri = pendingPlayURI {
            pendingPlayURI = nil
            appRemote.playerAPI?.play(uri, callback: { _, error in
                if let error { print("[SpotifyRemote] Pending play error: \(error)") }
            })
        }

        // Subscribe to player state
        appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
            if let error { print("[SpotifyRemote] Subscribe error: \(error)") }
        })
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        print("[SpotifyRemote] Disconnected: \(error?.localizedDescription ?? "unknown")")
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        print("[SpotifyRemote] Connection failed: \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate

extension SpotifyRemoteService: SPTAppRemotePlayerStateDelegate {

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let isPlaying = !playerState.isPaused
        let currentTime = TimeInterval(playerState.playbackPosition) / 1000.0
        let duration = TimeInterval(playerState.track.duration) / 1000.0

        let newState = PlaybackState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            trackId: playerState.track.uri
        )

        playbackStateSubject.send(newState)
    }
}
#endif // canImport(SpotifyiOS)
