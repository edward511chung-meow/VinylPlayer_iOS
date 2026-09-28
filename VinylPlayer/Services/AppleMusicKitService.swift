import Foundation
import MusicKit
import Combine
import SwiftUI

/// Apple Music integration using MusicKit's ApplicationMusicPlayer for TRUE in-app playback.
///
/// ## Requirements (will NOT work without these):
/// 1. Apple Developer Program enrollment ($99/year)
/// 2. Xcode → Signing & Capabilities → + → MusicKit
/// 3. In App Store Connect: enable MusicKit App Service
///
/// ## How to activate:
/// In `MusicServiceManager.init()`, change:
///   `services[.appleMusic] = AppleMusicService()`
/// to:
///   `services[.appleMusic] = AppleMusicKitService()`
///
/// ## What's different from AppleMusicService:
/// - Uses `ApplicationMusicPlayer.shared` instead of `MPMusicPlayerController.systemMusicPlayer`
/// - Music plays within the app's audio session (not the system Music app)
/// - Finds songs via MusicKit catalog ID (not MPMediaQuery local library search)
/// - Supports streaming from Apple Music catalog (user needs Apple Music subscription)
final class AppleMusicKitService: MusicService {

    let source: MusicSource = .appleMusic

    // MARK: - State

    private let authStatusSubject = CurrentValueSubject<MusicAuthStatus, Never>(.notDetermined)
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private var playbackTimer: Timer?

    var isAuthorized: Bool { authStatusSubject.value.isAuthorized }

    var authStatusPublisher: AnyPublisher<MusicAuthStatus, Never> {
        authStatusSubject.eraseToAnyPublisher()
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    /// In-app music player — plays within the app's own audio session.
    private let player = ApplicationMusicPlayer.shared

    /// Track duration and ID from the last play() call.
    private var currentPlayingDuration: TimeInterval = 0
    private var currentPlayingTrackId: String?

    // MARK: - Init

    init() {
        checkCurrentAuthStatus()
    }

    private func checkCurrentAuthStatus() {
        let status = MusicAuthorization.currentStatus
        authStatusSubject.send(mapAuthStatus(status))
    }

    private func mapAuthStatus(_ status: MusicAuthorization.Status) -> MusicAuthStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    // MARK: - Auth

    func authorize() async throws {
        let status = await MusicAuthorization.request()
        let mapped = mapAuthStatus(status)
        authStatusSubject.send(mapped)

        if case .denied = mapped { throw MusicServiceError.authorizationDenied }
        if case .restricted = mapped { throw MusicServiceError.authorizationRestricted }
    }

    func deauthorize() {
        authStatusSubject.send(.notDetermined)
        stopPlaybackPolling()
    }

    // MARK: - Library

    func fetchLibraryAlbums() async throws -> [Album] {
        guard isAuthorized else { throw MusicServiceError.notAuthorized }

        var request = MusicLibraryRequest<MusicKit.Album>()
        request.sort(by: \.libraryAddedDate, ascending: false)
        request.limit = 100

        let response = try await request.response()
        let items = Array(response.items)

        return try await withThrowingTaskGroup(of: Album.self, returning: [Album].self) { group in
            for mkAlbum in items {
                group.addTask { await self.convertAlbumWithTracks(mkAlbum) }
            }
            var results: [Album] = []
            results.reserveCapacity(items.count)
            for try await album in group { results.append(album) }
            return results
        }
    }

    func searchAlbums(query: String) async throws -> [Album] {
        guard isAuthorized else { throw MusicServiceError.notAuthorized }

        var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Album.self])
        request.limit = 25

        let response = try await request.response()
        let searchItems = Array(response.albums)

        return try await withThrowingTaskGroup(of: Album.self, returning: [Album].self) { group in
            for mkAlbum in searchItems {
                group.addTask { await self.convertAlbumWithTracks(mkAlbum) }
            }
            var results: [Album] = []
            results.reserveCapacity(searchItems.count)
            for try await album in group { results.append(album) }
            return results
        }
    }

    // MARK: - Playback (ApplicationMusicPlayer — in-app audio session)

    func play(track: Track, in album: Album) async throws {
        guard isAuthorized else { throw MusicServiceError.notAuthorized }

        let song: Song

        if let appleMusicId = track.appleMusicId {
            // Direct lookup by Apple Music catalog ID
            let songID = MusicItemID(appleMusicId)
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: songID)
            let response = try await request.response()
            guard let found = response.items.first else {
                throw MusicServiceError.trackNotAvailable
            }
            song = found
        } else {
            // Fallback: search by title + artist
            var searchRequest = MusicCatalogSearchRequest(
                term: "\(track.title) \(track.artist)",
                types: [Song.self]
            )
            searchRequest.limit = 5
            let response = try await searchRequest.response()

            let normalizedTitle = track.title.lowercased()
            let normalizedArtist = track.artist.lowercased()

            if let match = response.songs.first(where: {
                $0.title.lowercased() == normalizedTitle &&
                ($0.artistName.lowercased().contains(normalizedArtist) ||
                 normalizedArtist.contains($0.artistName.lowercased()))
            }) {
                song = match
            } else if let first = response.songs.first {
                song = first
            } else {
                throw MusicServiceError.trackNotAvailable
            }

            // Persist the discovered ID for future direct lookups
            await MainActor.run { track.appleMusicId = song.id.rawValue }
        }

        currentPlayingDuration = song.duration ?? track.duration
        currentPlayingTrackId = track.appleMusicId ?? song.id.rawValue

        // Queue the song and play using ApplicationMusicPlayer (in-app)
        player.queue = [song]
        try await player.play()

        print("[Playback] AppleMusicKitService: playing \(song.title) in-app")
        startPlaybackPolling()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        Task { try? await player.play() }
    }

    func seek(to progress: Double) {
        guard currentPlayingDuration > 0 else { return }
        player.playbackTime = currentPlayingDuration * progress
    }

    func skipToNext() {
        Task { try? await player.skipToNextEntry() }
    }

    func skipToPrevious() {
        Task { try? await player.skipToPreviousEntry() }
    }

    // MARK: - Apple Music Matching

    @discardableResult
    func matchTrack(_ track: Track) async -> Bool {
        guard isAuthorized, track.appleMusicId == nil else { return track.appleMusicId != nil }

        let query = "\(track.title) \(track.artist)"
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 5

        do {
            let response = try await request.response()
            let normalizedTitle = track.title.lowercased()
            let normalizedArtist = track.artist.lowercased()

            for song in response.songs {
                if song.title.lowercased() == normalizedTitle &&
                   (song.artistName.lowercased().contains(normalizedArtist) ||
                    normalizedArtist.contains(song.artistName.lowercased())) {
                    await MainActor.run { track.appleMusicId = song.id.rawValue }
                    return true
                }
            }

            if let first = response.songs.first, first.title.lowercased() == normalizedTitle {
                await MainActor.run { track.appleMusicId = first.id.rawValue }
                return true
            }
        } catch {
            print("AppleMusicKitService: match failed for \"\(track.title)\" — \(error)")
        }
        return false
    }

    @discardableResult
    func matchAlbumTracks(_ album: Album) async -> Int {
        guard isAuthorized else { return 0 }
        var matchCount = 0
        for track in album.tracks {
            if track.appleMusicId != nil { matchCount += 1; continue }
            if await matchTrack(track) { matchCount += 1 }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return matchCount
    }

    // MARK: - Lyrics

    func fetchTimeSyncedLyrics(for track: Track) async throws -> [LyricLine]? {
        let result = await LyricsService.shared.fetchSyncedLyrics(
            title: track.title, artist: track.artist,
            albumTitle: track.albumTitle, duration: track.duration
        )

        if let synced = result?.syncedLyrics, !synced.isEmpty {
            return LyricLine.fromLRC(synced)
        }
        if let plain = result?.plainLyrics, !plain.isEmpty {
            return parsePlainLyrics(plain)
        }
        if let lyrics = track.lyrics, !lyrics.isEmpty {
            return parsePlainLyrics(lyrics)
        }
        return nil
    }

    // MARK: - Player State Observation

    private func startPlaybackPolling() {
        stopPlaybackPolling()
        DispatchQueue.main.async { [weak self] in
            self?.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.updatePlaybackState()
            }
        }
    }

    private func stopPlaybackPolling() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updatePlaybackState() {
        let state = player.state
        let isPlaying = state.playbackStatus == .playing
        let currentTime = player.playbackTime

        let newState = PlaybackState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: currentPlayingDuration,
            trackId: currentPlayingTrackId
        )

        if newState != playbackStateSubject.value {
            playbackStateSubject.send(newState)
        }

        if state.playbackStatus == .stopped {
            stopPlaybackPolling()
        }
    }

    // MARK: - Conversion Helpers

    private func convertAlbumWithTracks(_ mkAlbum: MusicKit.Album) async -> Album {
        var artworkURL = mkAlbum.artwork?.url(width: 600, height: 600)?.absoluteString

        var tracks: [Track] = []
        do {
            let detailedAlbum = try await mkAlbum.with([.tracks, .artists])

            if artworkURL == nil {
                artworkURL = detailedAlbum.artwork?.url(width: 600, height: 600)?.absoluteString
            }
            if artworkURL == nil {
                artworkURL = await fetchCatalogArtwork(title: mkAlbum.title, artist: mkAlbum.artistName)
            }

            if let mkTracks = detailedAlbum.tracks {
                for (index, song) in mkTracks.enumerated() {
                    let discNumber = song.discNumber ?? 1
                    let side: VinylSide = discNumber <= 1
                        ? (index < mkTracks.count / 2 ? .a : .b)
                        : VinylSide(rawValue: String(Character(UnicodeScalar(64 + discNumber * 2 - 1)!))) ?? .a

                    let track = Track(
                        title: song.title,
                        artist: mkAlbum.artistName,
                        albumTitle: mkAlbum.title,
                        duration: song.duration ?? 0,
                        trackNumber: song.trackNumber ?? (index + 1),
                        discNumber: discNumber,
                        side: side,
                        appleMusicId: song.id.rawValue
                    )
                    tracks.append(track)
                }
            }
        } catch {
            print("Failed to fetch tracks for \(mkAlbum.title): \(error)")
        }

        var artworkData: Data?
        if let artworkURL, let url = URL(string: artworkURL) {
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: config)
                let (data, _) = try await session.data(from: url)
                if UIImage(data: data) != nil { artworkData = data }
            } catch {
                print("[Artwork] Download failed for \(mkAlbum.title): \(error.localizedDescription)")
            }
        }

        let album = Album(
            title: mkAlbum.title,
            artist: mkAlbum.artistName,
            releaseYear: mkAlbum.releaseDate.map { Calendar.current.component(.year, from: $0) },
            genre: mkAlbum.genreNames.first,
            colorHex: "#1A1A1A",
            tracks: tracks,
            appleMusicId: mkAlbum.id.rawValue,
            artworkURL: artworkURL
        )
        album.customCoverImageData = artworkData
        return album
    }

    private func fetchCatalogArtwork(title: String, artist: String) async -> String? {
        do {
            var request = MusicCatalogSearchRequest(
                term: "\(title) \(artist)", types: [MusicKit.Album.self]
            )
            request.limit = 3
            let response = try await request.response()

            for catalogAlbum in response.albums {
                let titleMatch = catalogAlbum.title.lowercased().contains(title.lowercased())
                    || title.lowercased().contains(catalogAlbum.title.lowercased())
                let artistMatch = catalogAlbum.artistName.lowercased().contains(artist.lowercased())
                    || artist.lowercased().contains(catalogAlbum.artistName.lowercased())

                if titleMatch && artistMatch, let artwork = catalogAlbum.artwork {
                    return artwork.url(width: 600, height: 600)?.absoluteString
                }
            }

            if let first = response.albums.first, let artwork = first.artwork {
                return artwork.url(width: 600, height: 600)?.absoluteString
            }
        } catch {
            print("[ArtworkFallback] Catalog search failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func parsePlainLyrics(_ content: String) -> [LyricLine] {
        let plainLines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return plainLines.enumerated().map { i, text in
            LyricLine(
                startTime: TimeInterval(i) * 4.0,
                endTime: TimeInterval(i + 1) * 4.0,
                text: text
            )
        }
    }
}
