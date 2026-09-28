import Foundation
import SwiftData

@Model
final class Track {
    var isFavorite: Bool = false
    var id: UUID
    var title: String
    var artist: String
    var albumTitle: String
    var duration: TimeInterval
    var trackNumber: Int
    var discNumber: Int
    var side: VinylSide

    // Lyrics
    var lyrics: String?

    // Streaming identifiers
    var appleMusicId: String?
    var spotifyURI: String?

    // Inverse relationship
    var album: Album?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        albumTitle: String = "",
        duration: TimeInterval = 0,
        trackNumber: Int = 1,
        discNumber: Int = 1,
        side: VinylSide = .a,
        lyrics: String? = nil,
        appleMusicId: String? = nil,
        spotifyURI: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.side = side
        self.lyrics = lyrics
        self.appleMusicId = appleMusicId
        self.spotifyURI = spotifyURI
    }
}

// MARK: - Vinyl Side

nonisolated enum VinylSide: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
}
