import Foundation
import SwiftUI
import SwiftData
func L(_ key: String) -> String { key }
struct AppConstants {
 static let rpm33 = 33.333
 struct StorageKeys {
  static let lastPlayedAlbumId = "queue-test-album"
  static let lastPlayedTrackId = "queue-test-track"
 }
}
struct NotificationManager { static let shared = Self(); func cancelListeningReminder() {} }
struct LiveActivityManager {
 static let shared = Self()
 func start(track: Track, album: Album) {}
 func switchTrack(track: Track, album: Album) {}
 func loadRemoteArtwork(for album: Album, track: Track) {}
 func update(isPlaying: Bool, progress: Double, elapsedTime: Double) {}
 func stop() {}
}
struct NowPlayingManager {
 static let shared = Self()
 func clearNowPlayingInfo() {}
 func updatePlaybackPosition(progress: Double, duration: Double, isPlaying: Bool) {}
 func updateNowPlayingInfo(track: Track, album: Album, isPlaying: Bool, progress: Double) {}
}
struct WidgetDataManager {
 static let shared = Self()
 func update(track: Track, album: Album, isPlaying: Bool, progress: Double, elapsedTime: Double) {}
}
struct PlaybackState {
 var isPlaying = false
 var currentTime: Double = 0
 var duration: Double = 0
 var progress: Double { duration > 0 ? currentTime / duration : 0 }
}
@main struct Check {
 @MainActor static func main() {
  func expect(_ value: @autoclosure () -> Bool, _ description: String) { precondition(value(), description); print("PASS: " + description) }
  let a = Album(title: "Album A", artist: "A", tracks: (1...4).map { Track(title: "A\($0)", artist: "A", duration: 120, trackNumber: $0) })
  let b = Album(title: "Album B", artist: "B", tracks: (1...2).map { Track(title: "B\($0)", artist: "B", duration: 120, trackNumber: $0) })
  let vm = CollectionViewModel()
  var selections: [String] = []
  vm.onPlaybackSelection = { track, _ in selections.append(track.title) }
  vm.play(album: a)
  expect(vm.playbackQueue.map(\.track.title) == ["A2", "A3", "A4"], "album tail materialized once")
  vm.moveInQueue(from: IndexSet(integer: 2), to: 0)
  vm.nextTrack()
  expect(vm.currentTrack?.title == "A4" && selections.last == "A4", "next follows reordered queue and requests actual track")
  vm.removeFromQueue(at: 0)
  expect(vm.playbackQueue.map(\.track.title) == ["A3"], "removed album track stays removed")
  vm.addToQueue(track: b.sortedTracks[0], album: b, playNext: true)
  vm.addToQueue(track: b.sortedTracks[0], album: b)
  let duplicateIDs = vm.playbackQueue.filter { $0.track.title == "B1" }.map(\.id)
  expect(duplicateIDs.count == 2 && Set(duplicateIDs).count == 2, "duplicate songs have separate identities")
  vm.playQueueItem(duplicateIDs[1])
  expect(vm.currentTrack?.title == "B1" && vm.playbackQueue.map(\.track.title) == ["B1", "A3"], "tap promotes only selected occurrence")
  vm.previousTrack()
  expect(vm.currentTrack?.title == "A4" && vm.currentAlbum?.id == a.id, "previous crosses album boundaries using history")
  vm.clearQueue()
  vm.repeatMode = .off
  vm.nextTrack()
  expect(!vm.isPlaying && vm.playbackQueue.isEmpty, "cleared queue stops without resurrecting album tracks")
  vm.play(album: a)
  vm.repeatMode = .one
  vm.nextTrack(automatically: true)
  expect(vm.currentTrack?.title == "A1", "repeat one repeats on natural completion")
  vm.nextTrack()
  expect(vm.currentTrack?.title == "A2", "manual next bypasses repeat one")
  let order = vm.playbackQueue.map(\.id)
  vm.toggleShuffle(); vm.toggleShuffle()
  expect(vm.playbackQueue.map(\.id) == order, "shuffle off restores remaining order")
  vm.play(album: a)
  let target = vm.playbackQueue[2]
  let count = selections.count
  vm.followSystemQueue(target.id)
  expect(vm.currentTrack?.title == "A4" && vm.playbackHistory.map(\.track.title) == ["A1", "A2", "A3"], "native background advance reconciles history")
  expect(selections.count == count, "native advance does not restart playback")
  vm.repeatMode = .all
  vm.nextTrack()
  expect(vm.currentTrack?.title == "A1" && vm.playbackQueue.map(\.track.title) == ["A2", "A3", "A4"], "repeat all cycles actual queue")
  let container = try! ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  container.mainContext.insert(a); container.mainContext.insert(b)
  try! container.mainContext.save()
  vm.addToQueue(track: b.sortedTracks[0], album: b)
  vm.addToQueue(track: b.sortedTracks[0], album: b)
  vm.playbackProgress = 0.4
  vm.repeatMode = .one
  vm.saveLastPlayed()
  let savedIDs = vm.playbackQueue.map(\.id)
  let restored = CollectionViewModel()
  restored.setModelContext(container.mainContext); restored.restoreLastPlayed()
  expect(restored.playbackQueue.map(\.id) == savedIDs && !restored.isPlaying, "restore preserves order and duplicate identities without autoplay")
  expect(restored.playbackProgress == 0.4 && restored.repeatMode == .one, "restore keeps elapsed position and repeat mode")
  restored.repeatMode = .all; restored.clearQueue()
  expect(restored.repeatMode == .off, "clear disables repeat all so history cannot return")
  let emptyRestored = CollectionViewModel()
  emptyRestored.setModelContext(container.mainContext); emptyRestored.restoreLastPlayed()
  expect(emptyRestored.playbackQueue.isEmpty, "empty queue stays empty after relaunch")
  let playlist = LibraryPlaylist(name: "Mixed")
  container.mainContext.insert(playlist)
  playlist.add([a.sortedTracks[0], b.sortedTracks[0], a.sortedTracks[0]])
  expect(playlist.trackIDs.count == 2, "playlist add is idempotent")
  playlist.trackIDs.reverse()
  vm.playTracks(playlist.tracks(in: a.tracks + b.tracks))
  expect(vm.currentTrack?.title == "B1" && vm.playbackQueue.first?.track.title == "A1", "playlist order plays across albums")
  vm.nextTrack()
  expect(vm.currentTrack?.title == "A1", "playlist next follows saved order")
  vm.applyPlaybackState(PlaybackState(isPlaying: false, currentTime: 24, duration: 120))
  expect(!vm.isPlaying && vm.playbackProgress == 0.2, "external pause and elapsed state reconcile without player view")
  vm.applyPlaybackState(PlaybackState(isPlaying: true, currentTime: 30, duration: 120))
  expect(vm.isPlaying && vm.playbackProgress == 0.25, "external resume reconciles")
  let currentID = vm.currentTrack?.id
  vm.play(album: Album(title: "Empty", artist: ""))
  expect(vm.currentTrack?.id == currentID, "empty album cannot destroy a playing queue")
  a.sortedTracks[0].isFavorite = true
  try! container.mainContext.save()
  let secondContext = ModelContext(container)
  expect(try! secondContext.fetch(FetchDescriptor<Track>()).contains { $0.isFavorite }, "favorite persists to store")
  let stored = try! secondContext.fetch(FetchDescriptor<LibraryPlaylist>()).first!
  expect(stored.trackIDs == playlist.trackIDs, "playlist order persists to store")
  container.mainContext.delete(playlist)
  try! container.mainContext.save()
  expect(a.tracks.count == 4 && b.tracks.count == 2, "deleting playlist preserves album songs")
  UserDefaults.standard.removeObject(forKey: "playbackQueue.v1")
  UserDefaults.standard.removeObject(forKey: AppConstants.StorageKeys.lastPlayedAlbumId)
  UserDefaults.standard.removeObject(forKey: AppConstants.StorageKeys.lastPlayedTrackId)
 }
}
