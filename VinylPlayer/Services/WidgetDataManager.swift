import Foundation
import WidgetKit
import UIKit

/// Manages writing playback data to the App Groups shared container
/// so the widget extension can read it.
@MainActor
final class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let sharedDefaults: UserDefaults?
    private var lastPlaybackWrite: Date = .distantPast

    private init() {
        sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId)
    }

    // MARK: - Write

    /// Update shared container with current playback state.
    func update(
        track: Track,
        album: Album,
        isPlaying: Bool,
        progress: Double,
        elapsedTime: TimeInterval,
        dominantColorHex: String? = nil
    ) {
        if let rawStyle = UserDefaults.standard.string(forKey: AppConstants.StorageKeys.turntableBaseStyle),
           let style = TurntableBaseStyle(rawValue: rawStyle) {
            updateBaseStyle(style)
        }
        var artworkData: Data?
        if let data = album.customCoverImageData,
           let image = UIImage(data: data),
           let thumb = resized(image, to: 200) {
            artworkData = thumb.jpegData(compressionQuality: 0.6)
        }

        let shared = SharedNowPlayingData(
            trackTitle: track.title,
            artist: track.artist,
            albumTitle: album.title,
            duration: track.duration,
            elapsedTime: elapsedTime,
            isPlaying: isPlaying,
            progress: progress,
            artworkData: artworkData,
            dominantColorHex: dominantColorHex,
            currentLyric: nil,
            previousLyric: nil,
            nextLyric: nil,
            lyricContext: nil,
            currentLyricContextIndex: nil,
            trackIdentity: track.id.uuidString,
            timedLyrics: LyricLine.fromLRC(track.lyrics ?? "").map { SharedLyricLine(startTime: $0.startTime, text: $0.text) },
            playbackSource: track.appleMusicId != nil ? SharedNowPlayingData.systemMusicSource : (track.spotifyURI != nil ? "spotify" : "local"),
            timestamp: Date()
        )

        lastPlaybackWrite = shared.timestamp
        save(shared)
        reloadWidgets()
    }

    /// Store appearance separately so existing playback snapshots remain compatible.
    func updateBaseStyle(_ style: TurntableBaseStyle) {
        let key = AppConstants.StorageKeys.turntableBaseStyle
        guard sharedDefaults?.string(forKey: key) != style.rawValue else { return }
        sharedDefaults?.set(style.rawValue, forKey: key)
        reloadWidgets()
    }

    /// Update only playback state (play/pause, progress) without changing track info.
    func updatePlaybackState(isPlaying: Bool, progress: Double, elapsedTime: TimeInterval, source: String? = nil) {
        guard var data = load() else { return }
        let now = Date()
        let stateChanged = data.isPlaying != isPlaying || (source != nil && data.playbackSource != source)
        let expectedElapsed = data.elapsedTime + (data.isPlaying ? now.timeIntervalSince(data.timestamp) : 0)
        let didSeek = abs(elapsedTime - expectedElapsed) >= 2
        guard stateChanged || didSeek || now.timeIntervalSince(lastPlaybackWrite) >= 5 else { return }
        if let source { data.playbackSource = source }
        data.isPlaying = isPlaying
        data.progress = progress
        data.elapsedTime = elapsedTime
        data.timestamp = now
        lastPlaybackWrite = now
        save(data)
        reloadWidgets()
    }

    /// Publish the complete schedule once when lyrics load/change. Independent
    /// of whether the full player is visible or currently moving to a new line.
    func updateTimedLyrics(_ lyrics: [LyricLine], trackIdentity: String) {
        guard var data = load(), data.trackIdentity == trackIdentity else { return }
        let lines = lyrics.filter { $0.startTime.isFinite && $0.startTime >= 0 }
            .sorted { $0.startTime < $1.startTime }
            .map { SharedLyricLine(startTime: $0.startTime, text: $0.text) }
        guard data.timedLyrics != lines else { return }
        data.timedLyrics = lines
        save(data)
        reloadWidgets()
    }

    /// Clear shared data when playback stops completely.
    func clear() {
        save(.empty)
        reloadWidgets()
    }

    // MARK: - Read

    /// Load current shared data (used by widget extension).
    func load() -> SharedNowPlayingData? {
        guard let data = sharedDefaults?.data(forKey: SharedNowPlayingData.userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedNowPlayingData.self, from: data)
    }

    // MARK: - Private

    private func save(_ nowPlaying: SharedNowPlayingData) {
        guard let encoded = try? JSONEncoder().encode(nowPlaying) else { return }
        sharedDefaults?.set(encoded, forKey: SharedNowPlayingData.userDefaultsKey)
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resized(_ image: UIImage, to maxSize: CGFloat) -> UIImage? {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}
