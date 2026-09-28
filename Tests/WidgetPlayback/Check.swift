import Foundation
import UIKit
struct AppConstants {
    static let appGroupId = "vinyl.widget.lyrics.check." + UUID().uuidString
    struct StorageKeys { static let turntableBaseStyle = "testBaseStyle" }
}
enum TurntableBaseStyle: String { case darkWalnut }
struct Track { let appleMusicId: String? = "test"; let spotifyURI: String? = nil; let id = UUID(); let title = "Test"; let artist = "Artist"; let duration: Double = 30; var lyrics: String? = "[00:05]First\n[00:10]Second" }
struct Album { let title = "Album"; let customCoverImageData: Data? = nil }
@main struct Check {
 @MainActor static func main() {
    let track = Track()
    let writer = WidgetDataManager.shared
    defer { UserDefaults(suiteName: AppConstants.appGroupId)?.removePersistentDomain(forName: AppConstants.appGroupId) }
    writer.update(track: track, album: Album(), isPlaying: true, progress: 0, elapsedTime: 0)
    var saved = writer.load()!
    precondition(saved.trackIdentity == track.id.uuidString && saved.timedLyrics?.count == 2)
    precondition(saved.projected(at: saved.timestamp.addingTimeInterval(11)).currentLyric == "Second")
    print("PASS: actual writer publishes persisted lyrics on track start")
    let lyrics = [LyricLine(startTime: 2, endTime: 8, text: "New first"), LyricLine(startTime: 8, endTime: nil, text: "New second")]
    writer.updateTimedLyrics(lyrics, trackIdentity: "stale track")
    precondition(writer.load()!.timedLyrics?.first?.text == "First")
    writer.updateTimedLyrics(lyrics, trackIdentity: track.id.uuidString)
    saved = writer.load()!
    precondition(saved.timedLyrics?.first?.text == "New first")
    print("PASS: late lyrics publish immediately, stale track results rejected")
    writer.updatePlaybackState(isPlaying: false, progress: 0.3, elapsedTime: 9)
    saved = writer.load()!
    precondition(saved.projected(at: Date().addingTimeInterval(20)).currentLyric == "New second")
    precondition(saved.lyricEntryDates(from: Date()).count == 1)
    print("PASS: actual pause write freezes timeline")
    precondition(!saved.isPlaying && saved.projected(at: Date().addingTimeInterval(20)).elapsedTime == 9)
    writer.updatePlaybackState(isPlaying: true, progress: 0.3, elapsedTime: 9, source: SharedNowPlayingData.systemMusicSource)
    precondition(writer.load()!.isPlaying && writer.load()!.playbackSource == SharedNowPlayingData.systemMusicSource)
    writer.updatePlaybackState(isPlaying: false, progress: 0.3, elapsedTime: 9, source: SharedNowPlayingData.systemMusicSource)
    precondition(!writer.load()!.isPlaying)
    print("PASS: rapid resume/pause bypasses progress write throttle")
    precondition(writer.load()!.usesSystemMusicPlayer)
    var otherSource = writer.load()!
    otherSource.playbackSource = "spotify"
    precondition(!otherSource.usesSystemMusicPlayer)
    otherSource.playbackSource = nil
    precondition(otherSource.usesSystemMusicPlayer)
    print("PASS: system source raw value and legacy snapshots are recognized")
    writer.clear()
    precondition(writer.load()?.hasTrack == false && writer.load()?.timedLyrics == nil)
    print("PASS: stop clears timed lyrics")
 }
}
