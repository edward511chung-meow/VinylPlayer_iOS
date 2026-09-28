import Foundation

/// Shared data model for passing Now Playing info between the main app and widget extension.
/// Stored in the App Groups shared container via UserDefaults.
struct SharedNowPlayingData: Codable {
    var trackTitle: String
    var artist: String
    var albumTitle: String
    var duration: TimeInterval
    var elapsedTime: TimeInterval
    var isPlaying: Bool
    var progress: Double          // 0...1
    var artworkData: Data?        // JPEG thumbnail
    var dominantColorHex: String? // Album dominant color for gradient background
    var currentLyric: String?     // Currently playing lyric line
    var previousLyric: String?    // Previous lyric line (for large widget context)
    var nextLyric: String?        // Next lyric line (for large widget context)
    var lyricContext: [String]?   // Up to three lines on either side of the current lyric
    var currentLyricContextIndex: Int?
    var trackIdentity: String? = nil
    var timedLyrics: [SharedLyricLine]? = nil
    var playbackSource: String? = nil
    var timestamp: Date           // When this data was last updated

    /// Key used to store/retrieve from UserDefaults shared container.
    static let userDefaultsKey = "nowPlayingData"

    /// Empty state for when nothing is playing.
    static let empty = SharedNowPlayingData(
        trackTitle: "",
        artist: "",
        albumTitle: "",
        duration: 0,
        elapsedTime: 0,
        isPlaying: false,
        progress: 0,
        artworkData: nil,
        dominantColorHex: nil,
        currentLyric: nil,
        previousLyric: nil,
        nextLyric: nil,
        lyricContext: nil,
        currentLyricContextIndex: nil,
        timestamp: Date()
    )

    static let systemMusicSource = "apple_music"

    /// Accept old snapshots that predate the source field or used the case name.
    var usesSystemMusicPlayer: Bool {
        playbackSource == nil || playbackSource == Self.systemMusicSource || playbackSource == "appleMusic"
    }

    /// Whether this represents actual playback data.
    var hasTrack: Bool {
        !trackTitle.isEmpty
    }
}

/// Sentence times only: WidgetKit renders snapshots, not live word animations.
struct SharedLyricLine: Codable, Equatable {
    let startTime: TimeInterval
    let text: String
}

extension SharedNowPlayingData {
    func projected(at date: Date) -> SharedNowPlayingData {
        var copy = self
        let elapsed = max(0, elapsedTime + (isPlaying ? max(0, date.timeIntervalSince(timestamp)) : 0))
        copy.elapsedTime = duration > 0 ? min(duration, elapsed) : elapsed
        copy.progress = duration > 0 ? min(1, copy.elapsedTime / duration) : progress
        if duration > 0 && elapsed >= duration { copy.isPlaying = false }
        copy.timestamp = date
        guard let lines = timedLyrics else { return copy } // Old snapshots remain readable.
        let index = lines.lastIndex { $0.startTime <= copy.elapsedTime }
        copy.currentLyric = index.map { lines[$0].text }
        copy.previousLyric = index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil }
        let next = index.map { $0 + 1 } ?? 0
        copy.nextLyric = lines.indices.contains(next) ? lines[next].text : nil
        let center = index ?? 0
        let lower = max(0, center - 3)
        let upper = min(lines.count, center + 4)
        copy.lyricContext = Array(lines[lower..<upper].map(\.text))
        copy.currentLyricContextIndex = index.map { $0 - lower }
        return copy
    }

    /// Precompute sentence boundaries from the playback anchor, even while the
    /// host app is suspended. WidgetKit may coalesce closely spaced entries.
    func lyricEntryDates(from now: Date) -> [Date] {
        guard hasTrack, isPlaying, projected(at: now).isPlaying else { return [now] }
        let boundaries = (timedLyrics ?? []).compactMap { line -> Date? in
            guard line.startTime.isFinite, line.startTime >= 0,
                  duration <= 0 || line.startTime < duration else { return nil }
            let date = timestamp.addingTimeInterval(line.startTime - elapsedTime)
            return date > now ? date : nil
        }
        var dates = [now] + Array(Set(boundaries).sorted().prefix(300))
        if duration > 0 && boundaries.count <= 300 {
            let end = timestamp.addingTimeInterval(duration - elapsedTime)
            if end > now { dates.append(end) }
        }
        return Array(Set(dates)).sorted()
    }
}
