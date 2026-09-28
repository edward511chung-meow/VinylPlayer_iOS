import Foundation
import Combine
import UIKit
import CommonCrypto

/// Spotify integration using Web API (OAuth 2.0 PKCE) + SpotifyiOS SDK for playback.
///
/// Architecture:
/// - Auth: OAuth 2.0 with PKCE via ASWebAuthenticationSession (no client secret needed)
/// - Library: Spotify Web API (albums, playlists, search)
/// - Playback: SPTAppRemote (requires Spotify app installed)
///
/// Note: SpotifyiOS SDK must be added via SPM or CocoaPods. The app remote connection
/// is handled when the Spotify app redirects back after auth.
final class SpotifyService: MusicService {

    let source: MusicSource = .spotify

    // MARK: - State

    private let authStatusSubject = CurrentValueSubject<MusicAuthStatus, Never>(.notDetermined)
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var codeVerifier: String?

    var isAuthorized: Bool { authStatusSubject.value.isAuthorized }

    var authStatusPublisher: AnyPublisher<MusicAuthStatus, Never> {
        authStatusSubject.eraseToAnyPublisher()
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    init() {
        loadStoredTokens()
    }

    // MARK: - Auth (OAuth 2.0 PKCE)

    func authorize() async throws {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        let authURL = buildAuthURL(challenge: challenge)

        // The actual auth flow is triggered via URL scheme
        // The app delegate / scene delegate should call handleCallback(url:)
        // when vinylplayer://spotify-callback is received

        // Store that we're waiting for auth
        await MainActor.run {
            // Open Spotify auth in browser
            UIApplication.shared.open(authURL)
        }
    }

    func deauthorize() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        clearStoredTokens()
        authStatusSubject.send(.notDetermined)
    }

    /// Handle the OAuth callback URL from Spotify.
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            authStatusSubject.send(.error("Invalid callback URL"))
            return
        }

        Task {
            do {
                try await exchangeCodeForToken(code: code, verifier: verifier)
                authStatusSubject.send(.authorized)
            } catch {
                authStatusSubject.send(.error(error.localizedDescription))
            }
        }
    }

    // MARK: - Library (Web API)

    func fetchLibraryAlbums() async throws -> [Album] {
        let token = try await validToken()

        let url = URL(string: "https://api.spotify.com/v1/me/albums?limit=50")!
        let data: SpotifySavedAlbumsResponse = try await spotifyRequest(url: url, token: token)

        return data.items.map { convertAlbum($0.album) }
    }

    func searchCatalog(query: String) async throws -> CatalogSearchResult {
        let token = try await validToken()
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
        let token = try await validToken()
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
        let token = try await validToken()

        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "limit", value: "25")
        ]

        let data: SpotifySearchResponse = try await spotifyRequest(url: components.url!, token: token)
        return data.albums.items.map { convertAlbum($0) }
    }

    /// Fetch tracks for a Spotify album.
    func fetchAlbumTracks(albumId: String) async throws -> [Track] {
        let token = try await validToken()

        let url = URL(string: "https://api.spotify.com/v1/albums/\(albumId)/tracks?limit=50")!
        let data: SpotifyTracksResponse = try await spotifyRequest(url: url, token: token)

        return data.items.enumerated().map { idx, item in
            Track(
                title: item.name,
                artist: item.artists.first?.name ?? "Unknown",
                duration: TimeInterval(item.durationMs) / 1000.0,
                trackNumber: item.trackNumber,
                discNumber: item.discNumber,
                side: item.discNumber <= 1 && item.trackNumber <= (data.items.count / 2 + 1) ? .a : .b,
                spotifyURI: item.uri
            )
        }
    }

    // MARK: - Playback (via Spotify Connect Web API)

    func play(track: Track, in album: Album) async throws {
        let token = try await validToken()

        guard let spotifyURI = track.spotifyURI else {
            throw MusicServiceError.trackNotAvailable
        }

        // Use Spotify Web API to start playback (requires active device)
        let url = URL(string: "https://api.spotify.com/v1/me/player/play")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["uris": [spotifyURI]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicServiceError.playbackFailed("Invalid response")
        }

        // 204 = success, 404 = no active device
        if httpResponse.statusCode == 404 {
            throw MusicServiceError.playbackFailed("No active Spotify device found. Open Spotify app first.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MusicServiceError.playbackFailed("HTTP \(httpResponse.statusCode)")
        }

        startPlaybackPolling()
    }

    func pause() {
        Task {
            let token = try? await validToken()
            guard let token else { return }

            let url = URL(string: "https://api.spotify.com/v1/me/player/pause")!
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func resume() {
        Task {
            let token = try? await validToken()
            guard let token else { return }

            let url = URL(string: "https://api.spotify.com/v1/me/player/play")!
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func seek(to progress: Double) {
        Task {
            let token = try? await validToken()
            guard let token else { return }
            let currentState = playbackStateSubject.value
            let positionMs = Int(progress * currentState.duration * 1000)

            var components = URLComponents(string: "https://api.spotify.com/v1/me/player/seek")!
            components.queryItems = [URLQueryItem(name: "position_ms", value: "\(positionMs)")]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func skipToNext() {
        Task {
            let token = try? await validToken()
            guard let token else { return }

            let url = URL(string: "https://api.spotify.com/v1/me/player/next")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func skipToPrevious() {
        Task {
            let token = try? await validToken()
            guard let token else { return }

            let url = URL(string: "https://api.spotify.com/v1/me/player/previous")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - Playback Polling

    private var pollingTimer: Timer?

    private func startPlaybackPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.pollPlaybackState()
            }
        }
    }

    private func pollPlaybackState() async {
        guard let token = try? await validToken() else { return }

        let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return }

        struct CurrentlyPlaying: Decodable {
            let isPlaying: Bool
            let progressMs: Int?
            let item: SpotifyTrackItem?

            enum CodingKeys: String, CodingKey {
                case isPlaying = "is_playing"
                case progressMs = "progress_ms"
                case item
            }
        }

        guard let playing = try? JSONDecoder().decode(CurrentlyPlaying.self, from: data) else { return }

        let newState = PlaybackState(
            isPlaying: playing.isPlaying,
            currentTime: TimeInterval(playing.progressMs ?? 0) / 1000.0,
            duration: TimeInterval(playing.item?.durationMs ?? 0) / 1000.0,
            trackId: playing.item?.uri
        )

        playbackStateSubject.send(newState)
    }

    // MARK: - Token Management

    private func validToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }

        if let refresh = refreshToken {
            try await refreshAccessToken(refreshToken: refresh)
            guard let token = accessToken else { throw MusicServiceError.notAuthorized }
            return token
        }

        throw MusicServiceError.notAuthorized
    }

    private func exchangeCodeForToken(code: String, verifier: String) async throws {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": APIConfig.Spotify.redirectURI,
            "client_id": APIConfig.Spotify.clientId,
            "code_verifier": verifier
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)

        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken ?? refreshToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        storeTokens()
    }

    private func refreshAccessToken(refreshToken: String) async throws {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": APIConfig.Spotify.clientId
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)

        accessToken = tokenResponse.accessToken
        if let newRefresh = tokenResponse.refreshToken {
            self.refreshToken = newRefresh
        }
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        storeTokens()
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(128)
            .description
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return "" }
        // SHA256 hash
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func buildAuthURL(challenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: APIConfig.Spotify.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: APIConfig.Spotify.redirectURI),
            URLQueryItem(name: "scope", value: APIConfig.Spotify.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        return components.url!
    }

    // MARK: - Keychain / UserDefaults Token Storage

    private let tokenKey = "spotify_access_token"
    private let refreshKey = "spotify_refresh_token"
    private let expiryKey = "spotify_token_expiry"

    private func storeTokens() {
        UserDefaults.standard.set(accessToken, forKey: tokenKey)
        UserDefaults.standard.set(refreshToken, forKey: refreshKey)
        UserDefaults.standard.set(tokenExpiry?.timeIntervalSince1970, forKey: expiryKey)
    }

    private func loadStoredTokens() {
        accessToken = UserDefaults.standard.string(forKey: tokenKey)
        refreshToken = UserDefaults.standard.string(forKey: refreshKey)
        if let expiry = UserDefaults.standard.object(forKey: expiryKey) as? Double {
            tokenExpiry = Date(timeIntervalSince1970: expiry)
        }
        if accessToken != nil, let expiry = tokenExpiry, expiry > Date() {
            authStatusSubject.send(.authorized)
        } else if refreshToken != nil {
            // Try to refresh on next use
            authStatusSubject.send(.authorized)
        }
    }

    private func clearStoredTokens() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Generic Spotify Request

    private func spotifyRequest<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("[SpotifyService] HTTP \(httpResponse.statusCode) from \(url.absoluteString)")
            print("[SpotifyService] Response: \(body)")
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Conversion

    private func convertAlbum(_ spotifyAlbum: SpotifyAlbum) -> Album {
        let artworkURL = spotifyAlbum.images.first?.url

        return Album(
            title: spotifyAlbum.name,
            artist: spotifyAlbum.artists.first?.name ?? "Unknown",
            releaseYear: spotifyAlbum.releaseDate.flatMap { Int(String($0.prefix(4))) },
            genre: nil,
            colorHex: "#1A1A1A",
            spotifyId: spotifyAlbum.id,
            artworkURL: artworkURL
        )
    }
}

// MARK: - Spotify API Response Models

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct SpotifySavedAlbumsResponse: Decodable {
    let items: [SpotifySavedAlbumItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct SpotifySavedAlbumItem: Decodable {
    let addedAt: String?
    let album: SpotifyAlbum

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case album
    }
}

struct SpotifySearchResponse: Decodable {
    let albums: SpotifyAlbumPaging
}

struct SpotifyAlbumPaging: Decodable {
    let items: [SpotifyAlbum]
    let total: Int
}

struct SpotifyAlbum: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let images: [SpotifyImage]
    let releaseDate: String?
    let totalTracks: Int?
    let uri: String

    enum CodingKeys: String, CodingKey {
        case id, name, artists, images, uri
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

struct SpotifyArtistSimple: Decodable {
    let id: String
    let name: String
}

struct SpotifyImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyTracksResponse: Decodable {
    let items: [SpotifyTrackItem]
    let total: Int
}

struct SpotifyTrackItem: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let durationMs: Int
    let trackNumber: Int
    let discNumber: Int
    let uri: String

    enum CodingKeys: String, CodingKey {
        case id, name, artists, uri
        case durationMs = "duration_ms"
        case trackNumber = "track_number"
        case discNumber = "disc_number"
    }
}
