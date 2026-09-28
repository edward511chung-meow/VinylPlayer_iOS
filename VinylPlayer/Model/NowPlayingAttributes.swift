import ActivityKit
import Foundation

/// Defines the data model for the Now Playing Live Activity.
/// Static attributes are set once when the activity starts.
/// ContentState is updated dynamically during playback.
struct NowPlayingAttributes: ActivityAttributes {
    /// Static data — set when activity starts, doesn't change.
    var trackTitle: String
    var artist: String
    var albumTitle: String
    var duration: TimeInterval
    /// Small thumbnail for Dynamic Island (max ~100x100).
    /// Stored as Data because ActivityKit can't share UIImage.
    var artworkData: Data?

    /// Dynamic data — updated as playback progresses.
    struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        var progress: Double        // 0...1
        var elapsedTime: TimeInterval
    }
}
