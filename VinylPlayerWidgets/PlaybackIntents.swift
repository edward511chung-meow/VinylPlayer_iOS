import AppIntents
import Foundation
import MusicKit
import MediaPlayer
import WidgetKit

// MARK: - Widget Style

enum WidgetTurntableStyle: String {
    case centered
    case tilted
    case radial
    case ripple
}

// MARK: - Toggle Play/Pause

struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var description: IntentDescription = "Play or pause the current track"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard WidgetPlaybackState.canControl else { return .result() }
        let player = SystemMusicPlayer.shared
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            try await player.play()
        }
        try? await Task.sleep(for: .milliseconds(200))
        WidgetPlaybackState.refresh(reload: true)
        return .result()
    }
}

// MARK: - Skip Next

struct SkipNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Next Track"
    static var description: IntentDescription = "Skip to the next track"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard WidgetPlaybackState.canControl else { return .result() }
        let player = SystemMusicPlayer.shared
        try await player.skipToNextEntry()
        try? await Task.sleep(for: .milliseconds(200))
        WidgetPlaybackState.refresh(reload: true)
        return .result()
    }
}

// MARK: - Skip Previous

struct SkipPreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Previous Track"
    static var description: IntentDescription = "Skip to the previous track"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard WidgetPlaybackState.canControl else { return .result() }
        let player = SystemMusicPlayer.shared
        try await player.skipToPreviousEntry()
        try? await Task.sleep(for: .milliseconds(200))
        WidgetPlaybackState.refresh(reload: true)
        return .result()
    }
}

/// Read the same system player used by AppleMusicService, including when the
/// host app is suspended. Never extrapolate a cached playing flag over a pause.
@MainActor
enum WidgetPlaybackState {
    static var canControl: Bool {
        guard let data = load() else { return false }
        return data.hasTrack && data.usesSystemMusicPlayer
    }

    static func load() -> SharedNowPlayingData? {
        guard let bytes = UserDefaults(suiteName: AppConstants.appGroupId)?.data(forKey: SharedNowPlayingData.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(SharedNowPlayingData.self, from: bytes)
    }

    @discardableResult
    static func refresh(reload: Bool = false) -> SharedNowPlayingData? {
        guard var data = load() else { return nil }
        guard data.hasTrack, data.usesSystemMusicPlayer else { return data }
        let player = MPMusicPlayerController.systemMusicPlayer
        let now = Date()
        let item = player.nowPlayingItem
        data.isPlaying = item != nil && player.playbackState == .playing
        let elapsed = player.currentPlaybackTime
        data.elapsedTime = elapsed.isFinite ? max(0, elapsed) : data.elapsedTime
        if let item {
            let title = item.title ?? ""
            let artist = item.artist ?? ""
            if data.trackTitle != title || data.artist != artist {
                // Do not show the previous song's lyrics/artwork after a skip.
                data.trackTitle = title
                data.artist = artist
                data.albumTitle = item.albumTitle ?? ""
                data.trackIdentity = nil
                data.timedLyrics = nil
                data.currentLyric = nil; data.previousLyric = nil; data.nextLyric = nil
                data.lyricContext = nil; data.currentLyricContextIndex = nil
                data.artworkData = item.artwork?.image(at: CGSize(width: 200, height: 200))?.jpegData(compressionQuality: 0.6)
                data.dominantColorHex = nil
            }
            data.duration = item.playbackDuration
        }
        data.progress = data.duration > 0 ? min(1, data.elapsedTime / data.duration) : 0
        data.timestamp = now
        data = data.projected(at: now)
        if let bytes = try? JSONEncoder().encode(data) {
            UserDefaults(suiteName: AppConstants.appGroupId)?.set(bytes, forKey: SharedNowPlayingData.userDefaultsKey)
        }
        if reload { WidgetCenter.shared.reloadAllTimelines() }
        return data
    }
}
