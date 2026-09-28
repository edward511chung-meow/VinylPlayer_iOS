import Foundation
import MediaPlayer
import UIKit

/// Manages the system NowPlaying Info Center and Remote Command Center.
/// Updates lock screen / Control Center with current track info and handles
/// remote playback commands (play, pause, next, previous, seek).
@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var collectionVM: CollectionViewModel?
    private var musicServiceManager: MusicServiceManager?

    private var artworkRequestID = UUID()
    private var commandsConfigured = false

    private init() {}

    // MARK: - Setup

    /// Call once at app launch to wire up remote commands.
    func configure(
        collectionVM: CollectionViewModel,
        musicServiceManager: MusicServiceManager
    ) {
        self.collectionVM = collectionVM
        self.musicServiceManager = musicServiceManager
        musicServiceManager.bindQueue(collectionVM)
        setupRemoteCommands()
    }

    // MARK: - Update Now Playing Info

    /// Update the lock screen / Control Center info for the current track.
    func updateNowPlayingInfo(
        track: Track,
        album: Album,
        isPlaying: Bool,
        progress: Double
    ) {
        let requestID = UUID()
        artworkRequestID = requestID
        var info = [String: Any]()

        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = album.title
        info[MPMediaItemPropertyPlaybackDuration] = track.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = track.duration * progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let trackNumber = Optional(track.trackNumber), trackNumber > 0 {
            info[MPMediaItemPropertyAlbumTrackNumber] = trackNumber
            info[MPMediaItemPropertyAlbumTrackCount] = album.tracks.count
        }

        // Album artwork
        if let data = album.customCoverImageData, let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let urlString = album.displayArtworkURL {
            // Load artwork asynchronously
            Task {
                if let image = await ImageCacheManager.shared.image(for: urlString) {
                    guard self.artworkRequestID == requestID else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    currentInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Update only the playback position and rate (avoids full info rebuild).
    func updatePlaybackPosition(progress: Double, duration: TimeInterval, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = duration * progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Clear now playing info when playback stops.
    func clearNowPlayingInfo() {
        artworkRequestID = UUID()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, let vm = self.collectionVM, let msm = self.musicServiceManager else {
                return .commandFailed
            }
            if !vm.isPlaying {
                msm.resume()
            }
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, let vm = self.collectionVM, let msm = self.musicServiceManager else {
                return .commandFailed
            }
            if vm.isPlaying {
                msm.pause()
            }
            return .success
        }

        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let vm = self.collectionVM, let msm = self.musicServiceManager else {
                return .commandFailed
            }
            if vm.isPlaying {
                msm.pause()
            } else {
                msm.resume()
            }
            return .success
        }

        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let vm = self.collectionVM, let msm = self.musicServiceManager else {
                return .commandFailed
            }
            vm.nextTrack()
            return .success
        }

        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let vm = self.collectionVM, let msm = self.musicServiceManager else {
                return .commandFailed
            }
            vm.previousTrack()
            return .success
        }

        // Seek
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let vm = self.collectionVM,
                  let msm = self.musicServiceManager,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let duration = vm.currentTrack?.duration ?? 0
            guard duration > 0 else { return .commandFailed }
            let progress = posEvent.positionTime / duration
            vm.playbackProgress = min(1, max(0, progress))
            msm.seek(to: vm.playbackProgress)
            return .success
        }
    }
}
