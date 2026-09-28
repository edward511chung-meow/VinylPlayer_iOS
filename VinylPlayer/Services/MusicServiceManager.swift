import SwiftUI
import Combine
import UIKit

/// Central manager that coordinates all music service backends.
/// Published properties drive the UI; the active service handles playback.
@MainActor
final class MusicServiceManager: ObservableObject {

    // MARK: - Published State

    struct PlaybackFailure {
        let trackID: UUID
        let title: String
        let message: String
    }
    @Published var isLoadingPlayback = false
    @Published var playbackFailure: PlaybackFailure?
    @Published private(set) var sleepPlan = SleepPlan()
    private var sleepTask: Task<Void, Never>?

    @Published var activeSource: MusicSource = .local
    @Published var authStatuses: [MusicSource: MusicAuthStatus] = [
        .appleMusic: .notDetermined,
        .spotify: .notDetermined,
        .local: .authorized
    ]
    @Published var playbackState = PlaybackState()
    @Published var currentLyrics: [LyricLine] = [] {
        didSet {
            if let identity = lyricTrackIdentity {
                WidgetDataManager.shared.updateTimedLyrics(currentLyrics, trackIdentity: identity)
            }
        }
    }
    @Published var currentLyricIndex: Int = 0
    @Published var isLoadingLibrary = false
    @Published var isLoadingLyrics = false

    // MARK: - Services

    private(set) var services: [MusicSource: MusicService] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var playbackTimer: Timer?

    /// In-memory lyrics cache (supplements SwiftData persistence).
    private var lyricTrackIdentity: String?
    private var lyricRequestID = UUID()
    private var lyricFetchTask: Task<Void, Never>?
    private var attemptedWordUpgrades = Set<String>()
    private var lyricsCache: [String: [LyricLine]] = [:]

    var activeService: MusicService? { services[activeSource] }

    // MARK: - In-App Playback Toggle

    /// Set to `true` to use ApplicationMusicPlayer (in-app playback).
    /// Requires: Apple Developer Program + MusicKit entitlement in Xcode.
    /// When `false`, uses MPMusicPlayerController.systemMusicPlayer (controls Music app).
    static let useInAppAppleMusic = false

    // MARK: - Init

    init() {
        let appleMusicService: MusicService = Self.useInAppAppleMusic
            ? AppleMusicKitService()
            : AppleMusicService()

        // SpotifyRemoteService is only available when SpotifyiOS SDK is installed.
        // Add via SPM: https://github.com/spotify/ios-sdk
        let spotifyService: MusicService
        #if canImport(SpotifyiOS)
        spotifyService = SpotifyRemoteService()
        #else
        spotifyService = SpotifyService()
        #endif

        services[.appleMusic] = appleMusicService
        services[.spotify] = spotifyService

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkSleepTimer() }
            .store(in: &cancellables)

        // Observe auth status from each service
        for (source, service) in services {
            service.authStatusPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.authStatuses[source] = status
                }
                .store(in: &cancellables)

            service.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self, self.activeSource == source else { return }
                    // Ignore observations from the previous song while a new selection loads.
                    guard self.queuePlayTask == nil else { return }
                    if self.sleepPlan.isExpired(at: .now) { self.checkSleepTimer(); return }
                    if let id = state.queueEntryID, let model = self.queueModel, model.currentQueueItem?.id != id {
                        self.loadedQueueEntryID = id
                        self.followingSystemQueue = true
                        model.followSystemQueue(id)
                        self.followingSystemQueue = false
                        if let track = model.currentTrack { self.refreshSystemQueueLyrics(for: track) }
                    }
                    if let model = self.queueModel, let track = model.currentTrack {
                        let matches = state.trackId != nil && (state.trackId == track.appleMusicId || state.trackId == track.spotifyURI)
                        guard matches || state.queueEntryID == model.currentQueueItem?.id && state.queueEntryID != nil else { return }
                        let wasPlaying = model.isPlaying
                        model.applyPlaybackState(state)
                        if state.didFinish, wasPlaying {
                            if self.sleepPlan.afterCurrentTrack { self.sleepPlan = SleepPlan() }
                            model.stopPlayback()
                        }
                        else if !(self.activeService is AppleMusicService), state.progress >= 1, wasPlaying {
                            model.nextTrack(automatically: true)
                        }
                    }
                    self.playbackState = state
                    self.updateCurrentLyricIndex()
                    WidgetDataManager.shared.updatePlaybackState(
                        isPlaying: state.isPlaying, progress: state.progress, elapsedTime: state.currentTime, source: source.rawValue
                    )
                }
                .store(in: &cancellables)
        }
    }

    private weak var queueModel: CollectionViewModel?
    private var queueSyncTask: Task<Void, Never>?
    private var queuePlayTask: Task<Void, Never>?
    private var queueRequestID = UUID()
    private var followingSystemQueue = false
    private var loadedQueueEntryID: UUID?

    func bindQueue(_ model: CollectionViewModel) {
        queueModel = model
        model.onPlaybackSelection = { [weak self, weak model] track, album in
            guard let self else { return }
            self.playbackFailure = nil
            self.isLoadingPlayback = true
            let resumeProgress = model?.playbackProgress ?? 0
            let previous = self.queuePlayTask
            previous?.cancel()
            let request = UUID()
            self.queueRequestID = request
            self.queuePlayTask = Task {
                await previous?.value
                defer { if self.queueRequestID == request { self.queuePlayTask = nil; self.isLoadingPlayback = false } }
                guard !Task.isCancelled else { return }
                do {
                    try await self.play(track: track, in: album)
                    if Task.isCancelled { self.activeService?.pause() }
                    else if resumeProgress > 0, resumeProgress < 1 { self.activeService?.seek(to: resumeProgress) }
                }
                catch {
                    if Task.isCancelled { self.activeService?.pause() }
                    else {
                        self.loadedQueueEntryID = nil
                        model?.stopPlayback()
                        self.playbackFailure = PlaybackFailure(trackID: track.id, title: track.title, message: error.localizedDescription)
                    }
                }
            }
        }
        model.onPlaybackStop = { [weak self] in self?.pause() }
        model.onQueueChanged = { [weak self] in self?.scheduleQueueSync() }
    }

    private func refreshSystemQueueLyrics(for track: Track) {
        lyricFetchTask?.cancel()
        isLoadingLyrics = false
        let request = UUID()
        lyricRequestID = request
        lyricTrackIdentity = track.id.uuidString
        currentLyrics = []
        preloadLyrics(for: track)
        guard !currentLyrics.contains(where: { !$0.words.isEmpty }) else { return }
        isLoadingLyrics = true
        lyricFetchTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.lyricRequestID == request { self.isLoadingLyrics = false } }
            let result = await LyricsService.shared.fetchSyncedLyrics(title: track.title, artist: track.artist, albumTitle: track.albumTitle, duration: track.duration)
            guard !Task.isCancelled, self.lyricRequestID == request, let raw = result?.syncedLyrics else { return }
            let lines = LyricLine.fromLRC(raw)
            guard !lines.isEmpty else { return }
            self.currentLyrics = lines
            track.lyrics = LyricLine.toLRC(lines)
        }
    }

    private func scheduleQueueSync() {
        guard !followingSystemQueue else { return }
        let previous = queueSyncTask
        previous?.cancel()
        queueSyncTask = Task {
            await previous?.value
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let model = queueModel,
                  let current = model.currentQueueItem, current.id == loadedQueueEntryID,
                  let service = activeService as? AppleMusicService else { return }
            do { try await service.synchronizeQueue(current: current, upcoming: self.sleepPlan.afterCurrentTrack ? [] : model.playbackQueue + (model.repeatMode == .all ? model.playbackHistory : []), repeatMode: self.sleepPlan.afterCurrentTrack ? .off : model.repeatMode) }
            catch { if !Task.isCancelled {
                if self.sleepPlan.afterCurrentTrack { self.sleepPlan = SleepPlan() }
                ToastManager.shared.error(L("queue.sync_failed")); print("[Queue] System queue sync failed: \(error)") } }
        }
    }

    var canSleepAfterTrack: Bool { activeService is AppleMusicService && queueModel?.currentTrack != nil }

    func retryPlayback() {
        guard let failure = playbackFailure, let model = queueModel,
              let track = model.currentTrack, let album = model.currentAlbum, track.id == failure.trackID else {
            playbackFailure = nil; return
        }
        model.onPlaybackSelection?(track, album)
    }

    func setSleepTimer(minutes: Int) {
        guard minutes > 0 else { return }
        cancelSleepTimer()
        let deadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepPlan = SleepPlan(deadline: deadline)
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Double(minutes) * 60)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.checkSleepTimer()
        }
    }

    func checkSleepTimer() {
        guard sleepPlan.isExpired(at: .now) else { return }
        sleepPlan = SleepPlan()
        sleepTask?.cancel(); sleepTask = nil
        pause()
    }

    func setSleepAfterTrack() {
        guard canSleepAfterTrack else { return }
        sleepTask?.cancel(); sleepTask = nil
        sleepPlan = SleepPlan(afterCurrentTrack: true)
        scheduleQueueSync()
    }

    func cancelSleepTimer() {
        let restoreQueue = sleepPlan.afterCurrentTrack
        sleepTask?.cancel(); sleepTask = nil
        sleepPlan = SleepPlan()
        if restoreQueue { scheduleQueueSync() }
    }

    // MARK: - Auth

    func authorize(source: MusicSource) async throws {
        guard let service = services[source] else { return }
        try await service.authorize()
    }

    func deauthorize(source: MusicSource) {
        services[source]?.deauthorize()
    }

    func isAuthorized(_ source: MusicSource) -> Bool {
        authStatuses[source]?.isAuthorized ?? false
    }

    // MARK: - Library

    func fetchLibraryAlbums(from source: MusicSource) async throws -> [Album] {
        guard let service = services[source] else { return [] }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        return try await service.fetchLibraryAlbums()
    }

    func searchAlbums(query: String, from source: MusicSource) async throws -> [Album] {
        guard let service = services[source] else { return [] }
        return try await service.searchAlbums(query: query)
    }

    func searchCatalog(query: String, source: MusicSource) async throws -> CatalogSearchResult {
        guard let service = services[source], isAuthorized(source) else { throw MusicServiceError.notAuthorized }
        return try await service.searchCatalog(query: query)
    }

    func loadCatalogTracks(_ album: Album, source: MusicSource) async throws {
        guard let service = services[source] else { throw MusicServiceError.trackNotAvailable }
        if album.tracks.isEmpty { album.tracks = try await service.loadTracks(for: album) }
        guard !album.tracks.isEmpty else { throw MusicServiceError.trackNotAvailable }
    }

    // MARK: - Playback

    func play(track: Track, in album: Album) async throws {
        // Determine which service can play this track
        let source = bestSource(for: track)
        guard let service = services[source] else { throw MusicServiceError.trackNotAvailable }
        if activeSource != source { activeService?.pause() }
        activeSource = source

        queueSyncTask?.cancel()
        await queueSyncTask?.value
        try Task.checkCancellation()
        let requestID = UUID()
        lyricRequestID = requestID
        // Reset lyrics immediately
        lyricTrackIdentity = nil
        currentLyrics = []
        lyricTrackIdentity = track.id.uuidString
        currentLyricIndex = 0

        // Cache key based on track identity
        let cacheKey = track.appleMusicId ?? "\(track.title)-\(track.artist)"

        // 1. Check SwiftData (persisted lyrics)
        if let lrcString = track.lyrics, !lrcString.isEmpty {
            let parsed = LyricLine.fromLRC(lrcString)
            if !parsed.isEmpty {
                lyricsCache[cacheKey] = parsed
                currentLyrics = parsed
            }
        }

        // 2. Check in-memory cache
        if currentLyrics.isEmpty, let cached = lyricsCache[cacheKey] {
            currentLyrics = cached
        }

        let needsFetch = currentLyrics.isEmpty || (!currentLyrics.contains { !$0.words.isEmpty } && !attemptedWordUpgrades.contains(cacheKey))
        if needsFetch { attemptedWordUpgrades.insert(cacheKey) }

        // Lyric lookup must not delay playback completion or keep an old song's
        // request alive after the user has selected another track.
        lyricFetchTask?.cancel()
        isLoadingLyrics = needsFetch
        if needsFetch {
            lyricFetchTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.lyricRequestID == requestID { self.isLoadingLyrics = false } }
                let result = await LyricsService.shared.fetchSyncedLyrics(
                    title: track.title, artist: track.artist,
                    albumTitle: track.albumTitle, duration: track.duration > 0 ? track.duration : nil
                )
                guard !Task.isCancelled, self.lyricRequestID == requestID else { return }
                let lyrics: [LyricLine]
                if let raw = result?.syncedLyrics {
                    lyrics = LyricLine.fromLRC(raw)
                } else {
                    // Retain the existing plain-text fallback. These estimated
                    // sentence times never become genuine word timing.
                    let plain = (result?.plainLyrics ?? track.lyrics ?? "")
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    lyrics = plain.enumerated().map { index, text in
                        LyricLine(startTime: Double(index) * 4, endTime: Double(index + 1) * 4, text: text)
                    }
                }
                guard !lyrics.isEmpty,
                      self.currentLyrics.isEmpty || lyrics.contains(where: { !$0.words.isEmpty }) else { return }
                self.lyricsCache[cacheKey] = lyrics
                self.currentLyrics = lyrics
                self.updateCurrentLyricIndex()
                track.lyrics = LyricLine.toLRC(lyrics)
            }
        }
        do {
            try Task.checkCancellation()
            try await service.play(track: track, in: album)
            if lyricRequestID == requestID {
                try Task.checkCancellation()
                loadedQueueEntryID = queueModel?.currentQueueItem?.id
                scheduleQueueSync()
            }
        }
        catch {
            if lyricRequestID == requestID {
                lyricFetchTask?.cancel()
                attemptedWordUpgrades.remove(cacheKey)
                isLoadingLyrics = false
            }
            throw error
        }
    }

    func pause() {
        queuePlayTask?.cancel()
        activeService?.pause()
        if let model = queueModel {
            let state = PlaybackState(isPlaying: false, currentTime: model.playbackProgress * (model.currentTrack?.duration ?? 0), duration: model.currentTrack?.duration ?? 0)
            model.applyPlaybackState(state)
            WidgetDataManager.shared.updatePlaybackState(isPlaying: false, progress: state.progress, elapsedTime: state.currentTime)
        }

    }
    func resume() {
        guard let model = queueModel, let track = model.currentTrack, let album = model.currentAlbum else { return }
        if loadedQueueEntryID == nil || loadedQueueEntryID != model.currentQueueItem?.id || model.playbackProgress >= 1 {
            model.onPlaybackSelection?(track, album)
        } else {
            activeService?.resume()
        }
    }
    func togglePlayback() {
        guard let model = queueModel, model.currentTrack != nil else { return }
        if model.isPlaying { pause() } else { resume() }
    }
    func seek(to progress: Double) {
        print("[Playback] seek to \(progress)")
        activeService?.seek(to: progress)
    }
    func skipToNext() { activeService?.skipToNext() }
    func skipToPrevious() { activeService?.skipToPrevious() }

    /// Check if the given track is the one currently loaded in the player.
    func isCurrentTrack(_ track: Track) -> Bool {
        guard let trackId = playbackState.trackId else { return false }
        return trackId == track.appleMusicId || trackId == track.spotifyURI
    }

    /// Preload lyrics from SwiftData/cache without resetting current state.
    /// Call this when the player UI appears so lyrics show immediately.
    func preloadLyrics(for track: Track) {
        guard currentLyrics.isEmpty else { return }
        lyricTrackIdentity = track.id.uuidString

        let cacheKey = track.appleMusicId ?? "\(track.title)-\(track.artist)"

        // 1. Check SwiftData
        if let lrcString = track.lyrics, !lrcString.isEmpty {
            let parsed = LyricLine.fromLRC(lrcString)
            if !parsed.isEmpty {
                lyricsCache[cacheKey] = parsed
                currentLyrics = parsed
                return
            }
        }

        // 2. Check in-memory cache
        if let cached = lyricsCache[cacheKey], !cached.isEmpty {
            currentLyrics = cached
        }
    }

    // MARK: - Helpers

    /// Pick the best service that can play this track.
    private func bestSource(for track: Track) -> MusicSource {
        if track.appleMusicId != nil, isAuthorized(.appleMusic) { return .appleMusic }
        if track.spotifyURI != nil, isAuthorized(.spotify) { return .spotify }
        return .local
    }

    private func updateCurrentLyricIndex() {
        let time = playbackState.currentTime
        guard !currentLyrics.isEmpty else { return }

        // Find the last lyric line whose startTime <= currentTime
        var idx = 0
        for (i, line) in currentLyrics.enumerated() {
            if line.startTime <= time { idx = i }
            else { break }
        }
        if idx != currentLyricIndex {
            currentLyricIndex = idx
        }
    }

    // MARK: - Spotify URL Handling

    func handleSpotifyCallback(url: URL) {
        #if canImport(SpotifyiOS)
        if let remote = services[.spotify] as? SpotifyRemoteService {
            remote.handleCallback(url: url)
            return
        }
        #endif
        (services[.spotify] as? SpotifyService)?.handleCallback(url: url)
    }
}
