import SwiftUI
import SwiftData
import Combine
import MediaPlayer

// MARK: - Repeat Mode

enum RepeatMode: String, CaseIterable {
    case off
    case all    // Repeat entire album / queue
    case one    // Repeat current track

    var iconName: String {
        switch self {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }

    var next: RepeatMode {
        switch self {
        case .off:  return .all
        case .all:  return .one
        case .one:  return .off
        }
    }
}

// MARK: - Queue Item

struct QueueItem: Identifiable {
    let id: UUID
    let track: Track
    let album: Album
    init(id: UUID = UUID(), track: Track, album: Album) {
        self.id = id; self.track = track; self.album = album
    }
}

/// Manages playback state. Album persistence is handled by SwiftData (@Query in views).
final class CollectionViewModel: ObservableObject {
    // Playback
    @Published var currentAlbum: Album?
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0
    @Published var currentRPM: Double = AppConstants.rpm33

    // Shuffle / Repeat
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off

    // Queue — tracks queued by user (cross-album "Up Next")
    @Published var playbackQueue: [QueueItem] = [] {
        didSet { saveQueue(); onQueueChanged?() }
    }
    @Published private(set) var playbackHistory: [QueueItem] = []
    @Published private(set) var currentQueueItem: QueueItem?
    var onPlaybackSelection: ((Track, Album) -> Void)?
    var onPlaybackStop: (() -> Void)?
    var onQueueChanged: (() -> Void)?
    private var unshuffledQueue: [QueueItem]?

    // Scrubber preview state (observed by ContentView to hide tab bar / mini player)
    @Published var isScrubberPreviewActive = false
    @Published var isAlbumDetailPresented = false


    // Listening history tracking
    private var playbackStartTime: Date?
    private var modelContext: ModelContext?

    /// Call once from a view that has access to the environment model context.
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Playback Controls

    func play(album: Album, track: Track? = nil) {
        guard !(album.tracks.isEmpty), track == nil || album.tracks.contains(where: { $0.id == track?.id }) else { return }
        // Record previous track's listening time before switching
        recordCurrentListening()

        currentAlbum = album
        currentTrack = track ?? album.sortedTracks.first
        currentRPM = album.selectedEdition?.format.rpm ?? AppConstants.rpm33
        isPlaying = true
        playbackProgress = 0
        playbackStartTime = Date()

        // Cancel listening reminder since user is playing now
        NotificationManager.shared.cancelListeningReminder()

        playbackHistory = []
        currentQueueItem = currentTrack.map { QueueItem(track: $0, album: album) }
        let sorted = album.sortedTracks
        let index = sorted.firstIndex { $0.id == currentTrack?.id } ?? 0
        let remaining = isShuffled ? sorted.filter { $0.id != currentTrack?.id }.shuffled() : Array(sorted.dropFirst(index + 1))
        unshuffledQueue = nil
        playbackQueue = remaining.map { QueueItem(track: $0, album: album) }

        // Start Live Activity
        if let t = currentTrack {
            LiveActivityManager.shared.start(track: t, album: album)
            if album.customCoverImageData == nil {
                LiveActivityManager.shared.loadRemoteArtwork(for: album, track: t)
            }
        }

        updateNowPlaying()
        saveLastPlayed()
        if let track = currentTrack { onPlaybackSelection?(track, album) }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if isPlaying {
            recordCurrentListening()
            playbackStartTime = nil
        } else {
            playbackStartTime = Date()
        }
        isPlaying.toggle()

        if currentTrack != nil {
            let elapsed = (currentTrack?.duration ?? 0) * playbackProgress
            LiveActivityManager.shared.update(
                isPlaying: isPlaying,
                progress: playbackProgress,
                elapsedTime: elapsed
            )
        }

        updateNowPlaying()
    }

    /// Stop playback and end the Live Activity.
    func stopPlayback() {
        recordCurrentListening()
        isPlaying = false
        playbackStartTime = nil
        LiveActivityManager.shared.stop()
        onPlaybackStop?()
        NowPlayingManager.shared.clearNowPlayingInfo()
        if let track = currentTrack, let album = currentAlbum {
            WidgetDataManager.shared.update(track: track, album: album, isPlaying: false, progress: playbackProgress, elapsedTime: track.duration * playbackProgress)
        }
        saveLastPlayed()
    }

    // MARK: - Track Navigation

    func nextTrack(automatically: Bool = false) {
        guard let current = currentQueueItem ?? currentTrack.flatMap({ track in currentAlbum.map { QueueItem(track: track, album: $0) } }) else { return }
        if automatically && repeatMode == .one {
            activate(current, rememberCurrent: false)
            return
        }
        if !playbackQueue.isEmpty {
            let item = playbackQueue.removeFirst()
            activate(item)
        } else if repeatMode == .all {
            let cycle = playbackHistory + [current]
            playbackHistory = []
            playbackQueue = Array(cycle.dropFirst())
            activate(cycle[0], rememberCurrent: false)
        } else {
            stopPlayback()
            playbackProgress = 1
        }
    }

    func previousTrack() {
        guard let current = currentQueueItem else { return }
        if playbackProgress * current.track.duration > 3 || playbackHistory.isEmpty {
            activate(current, rememberCurrent: false)
            return
        }
        let previous = playbackHistory.removeLast()
        playbackQueue.insert(current, at: 0)
        activate(previous, rememberCurrent: false)
    }

    private func activate(_ item: QueueItem, rememberCurrent: Bool = true, requestPlayback: Bool = true) {
        recordCurrentListening()
        if rememberCurrent, let current = currentQueueItem { playbackHistory.append(current) }
        currentQueueItem = item
        currentAlbum = item.album
        currentTrack = item.track
        currentRPM = item.album.selectedEdition?.format.rpm ?? AppConstants.rpm33
        playbackProgress = 0
        playbackStartTime = Date()
        isPlaying = true
        LiveActivityManager.shared.switchTrack(track: item.track, album: item.album)
        updateNowPlaying()
        saveLastPlayed()
        if requestPlayback { onPlaybackSelection?(item.track, item.album) }
    }

    /// Start an ordered cross-album selection using the same queue as album playback.
    func playTracks(_ tracks: [Track], startingAt id: UUID? = nil, shuffled: Bool = false) {
        let items = tracks.compactMap { track in track.album.map { QueueItem(track: track, album: $0) } }
        guard !items.isEmpty else { return }
        let index = id.flatMap { target in items.firstIndex { $0.track.id == target } } ?? 0
        let first = items[index]
        let remaining = shuffled ? items.filter { $0.id != first.id }.shuffled() : Array(items.dropFirst(index + 1))
        playbackHistory = []
        unshuffledQueue = nil
        isShuffled = shuffled
        playbackQueue = remaining
        activate(first, rememberCurrent: false)
    }

    /// Service observations remain authoritative even when the player UI is absent.
    func applyPlaybackState(_ state: PlaybackState) {
        if isPlaying != state.isPlaying {
            if !state.isPlaying { recordCurrentListening(); playbackStartTime = nil }
            else { playbackStartTime = Date() }
            isPlaying = state.isPlaying
        }
        if state.duration > 0, !isScrubberPreviewActive {
            playbackProgress = min(1, max(0, state.progress))
        }
        LiveActivityManager.shared.update(isPlaying: isPlaying, progress: playbackProgress, elapsedTime: state.currentTime)
        NowPlayingManager.shared.updatePlaybackPosition(progress: playbackProgress, duration: state.duration, isPlaying: isPlaying)
    }

    // MARK: - Queue Management

    func addToQueue(track: Track, album: Album, playNext: Bool = false) {
        let item = QueueItem(track: track, album: album)
        if currentTrack == nil { activate(item); return }
        if playNext { playbackQueue.insert(item, at: 0) }
        else { playbackQueue.append(item) }
    }

    func addAlbumToQueue(_ album: Album, playNext: Bool = false) {
        let items = album.sortedTracks.map { QueueItem(track: $0, album: album) }
        guard !items.isEmpty else { return }
        if currentTrack == nil {
            playbackQueue = Array(items.dropFirst())
            activate(items[0]); return
        }
        if playNext { playbackQueue.insert(contentsOf: items, at: 0) }
        else { playbackQueue.append(contentsOf: items) }
    }

    func removeFromQueue(at index: Int) {
        guard playbackQueue.indices.contains(index) else { return }
        playbackQueue.remove(at: index)
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard source.allSatisfy({ playbackQueue.indices.contains($0) }), (0...playbackQueue.count).contains(destination) else { return }
        playbackQueue.move(fromOffsets: source, toOffset: destination)
    }

    func clearQueue() {
        repeatMode = .off
        unshuffledQueue = nil
        playbackQueue.removeAll()
    }

    func playQueueItem(_ id: UUID) {
        guard let index = playbackQueue.firstIndex(where: { $0.id == id }) else { return }
        let selected = playbackQueue.remove(at: index)
        activate(selected)
    }

    func followSystemQueue(_ id: UUID) {
        guard currentQueueItem?.id != id else { return }
        let complete = playbackHistory + (currentQueueItem.map { [$0] } ?? []) + playbackQueue
        guard let index = complete.firstIndex(where: { $0.id == id }) else { return }
        let item = complete[index]
        playbackHistory = Array(complete.prefix(index))
        playbackQueue = Array(complete.dropFirst(index + 1))
        activate(item, rememberCurrent: false, requestPlayback: false)
    }

    func playHistoryItem(_ id: UUID) {
        guard let item = playbackHistory.first(where: { $0.id == id }) else { return }
        // Replaying history is a new occurrence, so duplicate songs remain independent.
        activate(QueueItem(track: item.track, album: item.album))
    }

    func replaceNowPlaying(with item: QueueItem, preserving upcoming: [QueueItem]) {
        playbackQueue = upcoming.filter { $0.id != item.id }
        activate(item)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            unshuffledQueue = playbackQueue
            playbackQueue.shuffle()
        } else if let original = unshuffledQueue {
            let ranks = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($0.element.id, $0.offset) })
            playbackQueue = playbackQueue.enumerated().sorted {
                (ranks[$0.element.id] ?? (original.count + $0.offset)) < (ranks[$1.element.id] ?? (original.count + $1.offset))
            }.map(\.element)
            unshuffledQueue = nil
        }
    }

    func cycleRepeatMode() { repeatMode = repeatMode.next; onQueueChanged?() }

    // MARK: - Now Playing

    /// Sync current track info to the system NowPlaying Info Center.
    private func updateNowPlaying() {
        guard let track = currentTrack, let album = currentAlbum else {
            NowPlayingManager.shared.clearNowPlayingInfo()
            return
        }
        NowPlayingManager.shared.updateNowPlayingInfo(
            track: track,
            album: album,
            isPlaying: isPlaying,
            progress: playbackProgress
        )
    }

    // MARK: - Last Played Persistence

    /// Save current track/album IDs to UserDefaults so the mini player can restore on next launch.
    func saveLastPlayed() {
        saveQueue()
        let defaults = UserDefaults.standard
        if let albumId = currentAlbum?.id.uuidString {
            defaults.set(albumId, forKey: AppConstants.StorageKeys.lastPlayedAlbumId)
        }
        if let trackId = currentTrack?.id.uuidString {
            defaults.set(trackId, forKey: AppConstants.StorageKeys.lastPlayedTrackId)
        }
    }

    private struct SavedQueueItem: Codable {
        let id: UUID
        let trackID: UUID
        let albumID: UUID
        init(_ item: QueueItem) { id = item.id; trackID = item.track.id; albumID = item.album.id }
    }
    private struct SavedQueue: Codable {
        let current: SavedQueueItem
        let upcoming: [SavedQueueItem]
        let history: [SavedQueueItem]
        var progress: Double? = nil
        var repeatValue: String? = nil
        var shuffled: Bool? = nil
    }
    private static let savedQueueKey = "playbackQueue.v1"
    private func saveQueue() {
        guard let current = currentQueueItem else { return }
        let snapshot = SavedQueue(current: SavedQueueItem(current), upcoming: playbackQueue.map { SavedQueueItem($0) }, history: playbackHistory.map { SavedQueueItem($0) }, progress: playbackProgress, repeatValue: repeatMode.rawValue, shuffled: isShuffled)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: Self.savedQueueKey) }
    }

    /// Restore last played track/album from UserDefaults + SwiftData. Does NOT auto-play.
    func restoreLastPlayed() {
        guard currentTrack == nil, let context = modelContext else { return }
        let defaults = UserDefaults.standard
        guard let albumIdStr = defaults.string(forKey: AppConstants.StorageKeys.lastPlayedAlbumId),
              let albumId = UUID(uuidString: albumIdStr) else { return }

        // Fetch album from SwiftData
        let albumPredicate = #Predicate<Album> { $0.id == albumId }
        var albumDesc = FetchDescriptor<Album>(predicate: albumPredicate)
        albumDesc.fetchLimit = 1
        guard let album = try? context.fetch(albumDesc).first else { return }

        currentAlbum = album
        currentRPM = album.selectedEdition?.format.rpm ?? AppConstants.rpm33

        // Restore track if saved
        if let trackIdStr = defaults.string(forKey: AppConstants.StorageKeys.lastPlayedTrackId),
           let trackId = UUID(uuidString: trackIdStr),
           let track = album.sortedTracks.first(where: { $0.id == trackId }) {
            currentTrack = track
        } else {
            currentTrack = album.sortedTracks.first
        }

        let saved = defaults.data(forKey: Self.savedQueueKey).flatMap { try? JSONDecoder().decode(SavedQueue.self, from: $0) }
        if let saved, saved.current.trackID == currentTrack?.id,
           let albums = try? context.fetch(FetchDescriptor<Album>()) {
            func item(_ value: SavedQueueItem) -> QueueItem? {
                guard let album = albums.first(where: { $0.id == value.albumID }),
                      let track = album.tracks.first(where: { $0.id == value.trackID }) else { return nil }
                return QueueItem(id: value.id, track: track, album: album)
            }
            currentQueueItem = item(saved.current)
            playbackHistory = saved.history.compactMap(item)
            playbackQueue = saved.upcoming.compactMap(item)
        } else {
            currentQueueItem = currentTrack.map { QueueItem(track: $0, album: album) }
            if let index = album.sortedTracks.firstIndex(where: { $0.id == currentTrack?.id }) {
                playbackQueue = album.sortedTracks.dropFirst(index + 1).map { QueueItem(track: $0, album: album) }
            }
        }
        // Show in mini player but don't play
        isPlaying = false
        playbackProgress = min(1, max(0, saved?.progress ?? 0))
        repeatMode = saved?.repeatValue.flatMap(RepeatMode.init(rawValue:)) ?? .off
        isShuffled = saved?.shuffled ?? false
    }

    // MARK: - Listening History

    private func recordCurrentListening() {
        guard let context = modelContext,
              let album = currentAlbum,
              let startTime = playbackStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        guard duration >= 5 else { return }

        let record = ListeningRecord(
            albumId: album.id,
            trackId: currentTrack?.id,
            albumTitle: album.title,
            trackTitle: currentTrack?.title,
            artist: album.artist,
            artworkURL: album.displayArtworkURL,
            listenDuration: duration
        )

        context.insert(record)
        try? context.save()
        playbackStartTime = nil
    }
}

// MARK: - Sort Order

enum AlbumSortOrder: String, CaseIterable, Identifiable {
    case recentlyAdded = "recently_added"
    case titleAZ = "title_az"
    case artist = "artist"
    case year = "year"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: return L("sort.recent")
        case .titleAZ: return L("sort.title")
        case .artist: return L("sort.artist")
        case .year: return L("sort.year")
        }
    }

    var iconName: String {
        switch self {
        case .recentlyAdded: return "clock"
        case .titleAZ: return "textformat.abc"
        case .artist: return "person"
        case .year: return "calendar"
        }
    }

    func sorted(_ albums: [Album]) -> [Album] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
        case .titleAZ:
            return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return albums.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .year:
            return albums.sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        }
    }
}
