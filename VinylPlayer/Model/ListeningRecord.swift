import Foundation
import SwiftData

@Model
final class ListeningRecord {
    var id: UUID
    var albumId: UUID
    var trackId: UUID?
    var albumTitle: String
    var trackTitle: String?
    var artist: String
    var artworkURL: String?
    var timestamp: Date
    var listenDuration: TimeInterval  // seconds actually listened

    init(
        id: UUID = UUID(),
        albumId: UUID,
        trackId: UUID? = nil,
        albumTitle: String,
        trackTitle: String? = nil,
        artist: String,
        artworkURL: String? = nil,
        timestamp: Date = Date(),
        listenDuration: TimeInterval = 0
    ) {
        self.id = id
        self.albumId = albumId
        self.trackId = trackId
        self.albumTitle = albumTitle
        self.trackTitle = trackTitle
        self.artist = artist
        self.artworkURL = artworkURL
        self.timestamp = timestamp
        self.listenDuration = listenDuration
    }
}
