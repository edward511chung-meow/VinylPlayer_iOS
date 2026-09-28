import ActivityKit
import SwiftUI
import Combine
import WidgetKit

/// Manages the Now Playing Live Activity lifecycle.
/// Call `start` when playback begins, `update` on progress/state changes,
/// and `stop` when playback ends.
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<NowPlayingAttributes>?

    private init() {}

    // MARK: - Public API

    /// Start a new Live Activity for the given track.
    func start(
        track: Track,
        album: Album,
        isPlaying: Bool = true
    ) {
        print("[LiveActivity] start() called — track: \(track.title), album: \(album.title)")

        // Don't start if track title is empty
        guard !track.title.isEmpty else {
            print("[LiveActivity] Skipping — empty track title")
            return
        }

        // End any existing activity first
        endCurrentActivity()

        // Home Screen widgets work independently of Live Activity permission
        // and whether Activity.request succeeds.
        WidgetDataManager.shared.update(
            track: track, album: album, isPlaying: isPlaying,
            progress: 0, elapsedTime: 0
        )

        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] Live Activities not enabled — check Settings or Info.plist NSSupportsLiveActivities")
            return
        }

        // Prepare tiny artwork thumbnail for Dynamic Island.
        // ActivityKit has a strict ~4KB limit on TOTAL attributes size
        // (all strings + data combined). We try JPEG at 40x40, quality 0.2.
        // If it's still too big, skip artwork entirely.
        var artworkData: Data? = nil
        if let thumbData = thumbnailData(for: album, maxSize: 40) {
            let totalEstimate = track.title.utf8.count + track.artist.utf8.count
                + album.title.utf8.count + 16 + thumbData.count
            if totalEstimate < 3800 {
                artworkData = thumbData
                print("[LiveActivity] Artwork data size: \(thumbData.count) bytes, total estimate: \(totalEstimate)")
            } else {
                print("[LiveActivity] Artwork too large (\(thumbData.count) bytes, total ~\(totalEstimate)). Skipping.")
            }
        }

        let attributes = NowPlayingAttributes(
            trackTitle: track.title,
            artist: track.artist,
            albumTitle: album.title,
            duration: track.duration,
            artworkData: artworkData
        )

        let initialState = NowPlayingAttributes.ContentState(
            isPlaying: isPlaying,
            progress: 0,
            elapsedTime: 0
        )

        print("[LiveActivity] Attributes — title: \(track.title), artist: \(track.artist), duration: \(track.duration), hasArtwork: \(artworkData != nil)")

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("[LiveActivity] Started successfully! Activity ID: \(currentActivity?.id ?? "nil")")
            print("[LiveActivity] Activity state: \(String(describing: currentActivity?.activityState))")

            // Debug: list all active activities
            let allActivities = Activity<NowPlayingAttributes>.activities
            print("[LiveActivity] Total active activities: \(allActivities.count)")
            for act in allActivities {
                print("[LiveActivity]   - \(act.id): state=\(act.activityState)")
            }
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Update the Live Activity with current playback state.
    func update(isPlaying: Bool, progress: Double, elapsedTime: TimeInterval) {
        WidgetDataManager.shared.updatePlaybackState(
            isPlaying: isPlaying, progress: progress, elapsedTime: elapsedTime
        )
        guard let activity = currentActivity else { return }

        let state = NowPlayingAttributes.ContentState(
            isPlaying: isPlaying,
            progress: progress,
            elapsedTime: elapsedTime
        )

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }

    }

    /// Update when switching tracks (need new attributes → restart activity).
    func switchTrack(track: Track, album: Album, isPlaying: Bool = true) {
        start(track: track, album: album, isPlaying: isPlaying)
    }

    /// End the Live Activity.
    func stop() {
        WidgetDataManager.shared.clear()
        endCurrentActivity()
    }

    /// Replacing a Live Activity must not clear the widget between tracks.
    private func endCurrentActivity() {
        guard let activity = currentActivity else { return }

        let finalState = NowPlayingAttributes.ContentState(
            isPlaying: false,
            progress: 0,
            elapsedTime: 0
        )

        Task {
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil

    }

    // MARK: - Helpers

    /// Generate a small thumbnail from the album's artwork.
    private func thumbnailData(for album: Album, maxSize: CGFloat) -> Data? {
        // Try local image data first
        if let data = album.customCoverImageData,
           let uiImage = UIImage(data: data) {
            return resized(uiImage, to: maxSize)?.jpegData(compressionQuality: 0.15)
        }

        // For remote URLs, the thumbnail will need to be loaded asynchronously
        // and updated later. Return nil for now — the UI handles missing artwork.
        return nil
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

    /// Load remote artwork asynchronously and restart activity with it.
    func loadRemoteArtwork(for album: Album, track: Track) {
        guard let urlString = album.displayArtworkURL,
              let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data),
                   let thumbData = resized(image, to: 60)?.jpegData(compressionQuality: 0.3) {
                    // Restart with artwork
                    let attributes = NowPlayingAttributes(
                        trackTitle: track.title,
                        artist: track.artist,
                        albumTitle: album.title,
                        duration: track.duration,
                        artworkData: thumbData
                    )

                    if let activity = currentActivity {
                        // Can't update attributes — need to restart
                        let state = NowPlayingAttributes.ContentState(
                            isPlaying: true,
                            progress: 0,
                            elapsedTime: 0
                        )
                        let content = ActivityContent(state: state, staleDate: nil)
                        await activity.end(content, dismissalPolicy: .immediate)

                        self.currentActivity = try? Activity.request(
                            attributes: attributes,
                            content: content,
                            pushType: nil
                        )
                    }
                }
            } catch {
                print("[LiveActivity] Failed to load artwork: \(error)")
            }
        }
    }
}
