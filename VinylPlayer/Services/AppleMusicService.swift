import Foundation
import MusicKit
import MediaPlayer
import Combine

/// Apple Music integration via MusicKit (library browsing) + MPMusicPlayerController (playback).
/// MPMusicPlayerController doesn't require a registered developer token,
/// so playback works without Apple Developer Program enrollment.
final class AppleMusicService: MusicService {

    let source: MusicSource = .appleMusic

    // MARK: - State

    private let authStatusSubject = CurrentValueSubject<MusicAuthStatus, Never>(.notDetermined)
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private var playbackTimer: Timer?
    private var playbackObservers: [NSObjectProtocol] = []

    var isAuthorized: Bool { authStatusSubject.value.isAuthorized }

    var authStatusPublisher: AnyPublisher<MusicAuthStatus, Never> {
        authStatusSubject.eraseToAnyPublisher()
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    /// Use systemMusicPlayer — controls the system Music app, no developer token needed.
    private let mpPlayer = MPMusicPlayerController.systemMusicPlayer

    // MARK: - Init

    init() {
        checkCurrentAuthStatus()
        mpPlayer.beginGeneratingPlaybackNotifications()
        for name in [Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange, .MPMusicPlayerControllerNowPlayingItemDidChange] {
            playbackObservers.append(NotificationCenter.default.addObserver(forName: name, object: mpPlayer, queue: .main) { [weak self] _ in
                self?.updatePlaybackState()
                if self?.mpPlayer.playbackState == .playing { self?.startPlaybackPolling() }
            })
        }
    }

    deinit {
        playbackObservers.forEach(NotificationCenter.default.removeObserver)
        playbackTimer?.invalidate()
        mpPlayer.endGeneratingPlaybackNotifications()
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

        if case .denied = mapped {
            throw MusicServiceError.authorizationDenied
        }
        if case .restricted = mapped {
            throw MusicServiceError.authorizationRestricted
        }
    }

    func deauthorize() {
        // MusicKit doesn't have explicit deauth — we just mark it
        // User needs to revoke in Settings > Privacy > Media & Apple Music
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
        let albums = try await withThrowingTaskGroup(of: Album.self, returning: [Album].self) { group in
            for mkAlbum in items {
                group.addTask {
                    await self.convertAlbumWithTracks(mkAlbum)
                }
            }
            var results: [Album] = []
            results.reserveCapacity(items.count)
            for try await album in group {
                results.append(album)
            }
            return results
        }
        return albums
    }

    func searchAlbums(query: String) async throws -> [Album] {
        guard isAuthorized else { throw MusicServiceError.notAuthorized }

        var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Album.self])
        request.limit = 25

        let response = try await request.response()
        let searchItems = Array(response.albums)
        let albums = try await withThrowingTaskGroup(of: Album.self, returning: [Album].self) { group in
            for mkAlbum in searchItems {
                group.addTask {
                    await self.convertAlbumWithTracks(mkAlbum)
                }
            }
            var results: [Album] = []
            results.reserveCapacity(searchItems.count)
            for try await album in group {
                results.append(album)
            }
            return results
        }
        return albums
    }

    // MARK: - Playback (via MPMusicPlayerController — no developer token needed)

    func play(track: Track, in album: Album) async throws {
        print("[Playback] AppleMusicService.play() — track: \(track.title), artist: \(track.artist)")

        guard isAuthorized else {
            print("[Playback] Not authorized!")
            throw MusicServiceError.notAuthorized
        }

        let mediaItem = findMediaItem(title: track.title, artist: track.artist, album: album.title)
        nativeQueue = []
        mpPlayer.repeatMode = .none
        mpPlayer.shuffleMode = .off
        currentPlayingDuration = mediaItem?.playbackDuration ?? track.duration
        currentPlayingTrackId = track.appleMusicId
        if let mediaItem {
            mpPlayer.setQueue(with: MPMediaItemCollection(items: [mediaItem]))
        } else if let id = track.appleMusicId, !id.isEmpty, id.allSatisfy(\.isNumber) {
            // Catalog results need not already be in the device library.
            mpPlayer.setQueue(with: [id])
        } else { throw MusicServiceError.trackNotAvailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            mpPlayer.prepareToPlay { error in
                if let error { continuation.resume(throwing: MusicServiceError.playbackFailed(error.localizedDescription)) }
                else { continuation.resume() }
            }
        }
        try Task.checkCancellation()
        playbackCommandVersion += 1
        mpPlayer.play()
        startPlaybackPolling()
    }

    private var nativeQueue: [QueueItem] = []
    private var replacingQueue = false
    private var playbackCommandVersion = 0

    /// Give the system player the actual upcoming order so it can continue
    /// while our app is suspended. Validate everything before replacing it.
    func synchronizeQueue(current: QueueItem, upcoming: [QueueItem], repeatMode: RepeatMode) async throws {
        let entries = [current] + upcoming
        let media = entries.map { findMediaItem(title: $0.track.title, artist: $0.track.artist, album: $0.album.title) }
        let storeIDs = entries.compactMap { $0.track.appleMusicId }
        let allLocal = media.allSatisfy { $0 != nil }
        guard allLocal || (storeIDs.count == entries.count && storeIDs.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw MusicServiceError.trackNotAvailable
        }
        let elapsed = max(0, mpPlayer.currentPlaybackTime)
        let playing = mpPlayer.playbackState == .playing
        let commandVersion = playbackCommandVersion
        replacingQueue = true
        defer { replacingQueue = false }
        mpPlayer.shuffleMode = .off // The app already materialized the shuffled order.
        mpPlayer.repeatMode = repeatMode == .one ? .one : (repeatMode == .all ? .all : .none)
        if allLocal { mpPlayer.setQueue(with: MPMediaItemCollection(items: media.compactMap { $0 })) }
        else { mpPlayer.setQueue(with: storeIDs) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            mpPlayer.prepareToPlay { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        nativeQueue = entries
        mpPlayer.currentPlaybackTime = elapsed
        try Task.checkCancellation()
        if playing && commandVersion == playbackCommandVersion { mpPlayer.play() }
        startPlaybackPolling()
    }

    /// Find a song in the device's local media library by title + artist.
    private func findMediaItem(title: String, artist: String, album: String) -> MPMediaItem? {
        let normalizedTitle = title.lowercased()
        let normalizedArtist = artist.lowercased()

        // Try exact title + artist match first
        let titlePredicate = MPMediaPropertyPredicate(
            value: title,
            forProperty: MPMediaItemPropertyTitle,
            comparisonType: .contains
        )
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(titlePredicate)

        if let items = query.items {
            // Best match: title + artist both match
            for item in items {
                let itemTitle = (item.title ?? "").lowercased()
                let itemArtist = (item.artist ?? "").lowercased()
                let albumMatches = album.isEmpty || (item.albumTitle ?? "").caseInsensitiveCompare(album) == .orderedSame
                if itemTitle == normalizedTitle && albumMatches &&
                   (itemArtist.contains(normalizedArtist) || normalizedArtist.contains(itemArtist)) {
                    return item
                }
            }


        }

        print("[Playback] No MPMediaItem found for \"\(title)\" by \"\(artist)\"")
        return nil
    }

    func pause() {
        playbackCommandVersion += 1
        mpPlayer.pause()
        updatePlaybackState()
    }

    func resume() {
        playbackCommandVersion += 1
        mpPlayer.play()
        startPlaybackPolling()
    }

    func seek(to progress: Double) {
        let currentState = playbackStateSubject.value
        guard currentState.duration > 0 else { return }
        mpPlayer.currentPlaybackTime = currentState.duration * progress
    }

    func skipToNext() {
        mpPlayer.skipToNextItem()
    }

    func skipToPrevious() {
        mpPlayer.skipToPreviousItem()
    }

    // MARK: - Apple Music Matching

    /// Match a single track to Apple Music catalog and set its appleMusicId.
    /// Returns true if a match was found.
    @discardableResult
    func matchTrack(_ track: Track) async -> Bool {
        guard isAuthorized else { return false }
        guard track.appleMusicId == nil else { return true }

        let query = "\(track.title) \(track.artist)"
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 5

        do {
            let response = try await request.response()
            let normalizedTitle = track.title.lowercased()
            let normalizedArtist = track.artist.lowercased()

            for song in response.songs {
                let songTitle = song.title.lowercased()
                let songArtist = song.artistName.lowercased()

                if songTitle == normalizedTitle &&
                   (songArtist.contains(normalizedArtist) || normalizedArtist.contains(songArtist)) {
                    await MainActor.run {
                        track.appleMusicId = song.id.rawValue
                    }
                    return true
                }
            }

            // Fallback: first result with matching title
            if let first = response.songs.first,
               first.title.lowercased() == normalizedTitle {
                await MainActor.run {
                    track.appleMusicId = first.id.rawValue
                }
                return true
            }
        } catch {
            print("AppleMusicService: match failed for \"\(track.title)\" — \(error.localizedDescription)")
        }
        return false
    }

    /// Match all tracks in an album to Apple Music. Returns number of tracks matched.
    @discardableResult
    func matchAlbumTracks(_ album: Album) async -> Int {
        guard isAuthorized else { return 0 }

        var matchCount = 0
        for track in album.tracks {
            if track.appleMusicId != nil {
                matchCount += 1
                continue
            }
            if await matchTrack(track) { matchCount += 1 }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return matchCount
    }

    // MARK: - Lyrics

    /// Fetch lyrics for a track.
    /// Priority: LRCLIB synced (real timestamps) > LRCLIB plain > stored plain lyrics.
    func fetchTimeSyncedLyrics(for track: Track) async throws -> [LyricLine]? {
        // Always try LRCLIB first for synced lyrics with real timestamps
        let result = await LyricsService.shared.fetchSyncedLyrics(
            title: track.title,
            artist: track.artist,
            albumTitle: track.albumTitle,
            duration: track.duration
        )

        // Best: synced lyrics with [mm:ss.xx] timestamps
        if let synced = result?.syncedLyrics, !synced.isEmpty {
            print("[Lyrics] Got synced lyrics from LRCLIB for \(track.title)")
            return parseLRC(synced)
        }

        // Second: plain lyrics from LRCLIB
        if let plain = result?.plainLyrics, !plain.isEmpty {
            print("[Lyrics] Got plain lyrics from LRCLIB for \(track.title)")
            return parsePlainLyrics(plain)
        }

        // Fallback: stored plain lyrics (from import)
        if let lyrics = track.lyrics, !lyrics.isEmpty {
            print("[Lyrics] Using stored plain lyrics for \(track.title) (no timestamps)")
            return parsePlainLyrics(lyrics)
        }

        return nil
    }

    // LRCLIB lyrics fetching is now handled by LyricsService.shared

    // MARK: - Player State Observation

    private func startPlaybackPolling() {
        stopPlaybackPolling()
        // Ensure timer runs on main RunLoop
        DispatchQueue.main.async { [weak self] in
            self?.playbackTimer?.invalidate()
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
        guard !replacingQueue else { return }
        let queueIndex = mpPlayer.indexOfNowPlayingItem
        let item = nativeQueue.indices.contains(queueIndex) ? nativeQueue[queueIndex] : nil
        if let item {
            currentPlayingDuration = mpPlayer.nowPlayingItem?.playbackDuration ?? item.track.duration
            currentPlayingTrackId = item.track.appleMusicId
        }
        let currentTime = mpPlayer.currentPlaybackTime
        let isPlaying = mpPlayer.playbackState == .playing

        let newState = PlaybackState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: currentPlayingDuration,
            trackId: currentPlayingTrackId,
            queueEntryID: item?.id,
            didFinish: mpPlayer.playbackState == .stopped && !nativeQueue.isEmpty
        )

        if newState != playbackStateSubject.value {
            playbackStateSubject.send(newState)
        }

        // Stop polling if stopped
        if mpPlayer.playbackState == .stopped || mpPlayer.playbackState == .interrupted {
            stopPlaybackPolling()
        }
    }

    // Track duration and ID from the last play() call
    private var currentPlayingDuration: TimeInterval = 0
    private var currentPlayingTrackId: String?

    // MARK: - Conversion Helpers

    /// Convert a MusicKit album WITH its tracks loaded.
    private func convertAlbumWithTracks(_ mkAlbum: MusicKit.Album) async -> Album {
        var artworkURL = mkAlbum.artwork?.url(width: 600, height: 600)?.absoluteString

        // Fetch tracks for this album
        var tracks: [Track] = []
        do {
            let detailedAlbum = try await mkAlbum.with([.tracks, .artists])

            // Try artwork from detailed album if original was nil
            if artworkURL == nil {
                artworkURL = detailedAlbum.artwork?.url(width: 600, height: 600)?.absoluteString
            }

            // Fallback: search catalog by album name + artist for artwork
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
            // If track fetch fails, still create the album without tracks
            print("Failed to fetch tracks for \(mkAlbum.title): \(error)")
        }

        // Download artwork data immediately for local storage
        var artworkData: Data?
        if let artworkURL, let url = URL(string: artworkURL) {
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: config)
                let (data, _) = try await session.data(from: url)
                if UIImage(data: data) != nil {
                    artworkData = data
                }
            } catch {
                print("[Artwork] Failed to download artwork for \(mkAlbum.title): \(error.localizedDescription)")
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

    /// Lightweight conversion without fetching tracks (for quick display).
    private func convertAlbum(_ mkAlbum: MusicKit.Album) -> Album {
        let artworkURL = mkAlbum.artwork?.url(width: 600, height: 600)?.absoluteString

        return Album(
            title: mkAlbum.title,
            artist: mkAlbum.artistName,
            releaseYear: mkAlbum.releaseDate.map { Calendar.current.component(.year, from: $0) },
            genre: mkAlbum.genreNames.first,
            colorHex: "#1A1A1A",
            appleMusicId: mkAlbum.id.rawValue,
            artworkURL: artworkURL
        )
    }

    // MARK: - Catalog Artwork Fallback

    /// Search Apple Music catalog for artwork when library album has none.
    private func fetchCatalogArtwork(title: String, artist: String) async -> String? {
        do {
            var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [MusicKit.Album.self])
            request.limit = 3
            let response = try await request.response()

            // Find best match
            for catalogAlbum in response.albums {
                let titleMatch = catalogAlbum.title.lowercased().contains(title.lowercased())
                    || title.lowercased().contains(catalogAlbum.title.lowercased())
                let artistMatch = catalogAlbum.artistName.lowercased().contains(artist.lowercased())
                    || artist.lowercased().contains(catalogAlbum.artistName.lowercased())

                if titleMatch && artistMatch, let artwork = catalogAlbum.artwork {
                    return artwork.url(width: 600, height: 600)?.absoluteString
                }
            }

            // If no exact match, use first result's artwork
            if let first = response.albums.first, let artwork = first.artwork {
                return artwork.url(width: 600, height: 600)?.absoluteString
            }
        } catch {
            print("[ArtworkFallback] Catalog search failed for \(title): \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Lyrics Parsing

    /// Parse LRC format: [mm:ss.xx] text
    private func parseLRC(_ content: String) -> [LyricLine] {
        LyricLine.fromLRC(content)
    }

    /// Parse plain text lyrics (no timestamps) — estimate timing.
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

// MARK: - Errors

enum MusicServiceError: LocalizedError {
    case notAuthorized
    case authorizationDenied
    case authorizationRestricted
    case trackNotAvailable
    case playbackFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return L("playback.not_authorized")
        case .authorizationDenied: return "Access denied — enable in Settings > Privacy"
        case .authorizationRestricted: return "Access restricted on this device"
        case .trackNotAvailable: return L("playback.unavailable")
        case .playbackFailed(let msg): return "Playback failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}
