import Foundation
import SwiftUI
import SwiftData

@Model
final class Album {
    var id: UUID
    var title: String
    var artist: String
    var releaseYear: Int?
    var genre: String?
    var colorHex: String

    @Relationship(deleteRule: .cascade, inverse: \Track.album)
    var tracks: [Track] = []

    @Relationship(deleteRule: .cascade, inverse: \VinylEdition.album)
    var editions: [VinylEdition] = []

    var selectedEditionId: UUID?
    var enrichmentReceipt: Data?
    var customCoverImageData: Data?

    // Apple Music / Spotify identifiers
    var appleMusicId: String?
    var spotifyId: String?
    var artworkURL: String?

    // Collection metadata
    var addedDate: Date?
    var tags: [String] = []

    // Custom vinyl color override (hex string, e.g. "#FF0000")
    var customVinylColorHex: String?

    // Custom vinyl opacity (0.4 – 1.0, nil = 1.0 fully opaque)
    var vinylOpacity: Double?

    // Pin to top of collection
    var isPinned: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        releaseYear: Int? = nil,
        genre: String? = nil,
        colorHex: String = "#1A1A1A",
        tracks: [Track] = [],
        editions: [VinylEdition] = [],
        selectedEditionId: UUID? = nil,
        customCoverImageData: Data? = nil,
        appleMusicId: String? = nil,
        spotifyId: String? = nil,
        artworkURL: String? = nil,
        addedDate: Date? = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.releaseYear = releaseYear
        self.genre = genre
        self.colorHex = colorHex
        self.tracks = tracks
        self.editions = editions
        self.selectedEditionId = selectedEditionId
        self.customCoverImageData = customCoverImageData
        self.appleMusicId = appleMusicId
        self.spotifyId = spotifyId
        self.artworkURL = artworkURL
        self.addedDate = addedDate
    }

    // MARK: - Computed

    var color: Color {
        Color(hex: colorHex) ?? .gray
    }

    /// The effective vinyl color hex — custom override takes priority, then edition color, then default black.
    var effectiveVinylColorHex: String {
        if let custom = customVinylColorHex, !custom.isEmpty {
            return custom
        }
        return selectedEdition?.vinylColor.colorHex ?? "#1A1A1A"
    }

    /// Whether the vinyl is using a user-customized color (not a preset).
    var hasCustomVinylColor: Bool {
        customVinylColorHex != nil && !(customVinylColorHex?.isEmpty ?? true)
    }

    /// The effective vinyl color as a SwiftUI Color.
    var effectiveVinylColor: Color {
        Color(hex: effectiveVinylColorHex) ?? Color(white: 0.1)
    }

    /// The effective vinyl opacity (0.4 – 1.0). Defaults to 1.0 when nil.
    var effectiveVinylOpacity: Double {
        vinylOpacity ?? 1.0
    }

    var usesTransparentVinyl: Bool {
        let editionOpacity = hasCustomVinylColor ? 1 : (selectedEdition?.vinylColor.discOpacity ?? 1)
        return editionOpacity * effectiveVinylOpacity < 0.99
    }

    var selectedEdition: VinylEdition? {
        guard let edId = selectedEditionId else { return editions.first }
        return editions.first(where: { $0.id == edId }) ?? editions.first
    }

    var displayArtworkURL: String? {
        selectedEdition?.coverImageURL ?? artworkURL
    }

    /// Tracks sorted by disc number then track number.
    var sortedTracks: [Track] {
        tracks.sorted { a, b in
            if a.discNumber != b.discNumber { return a.discNumber < b.discNumber }
            return a.trackNumber < b.trackNumber
        }
    }

    // MARK: - Duplicate Detection

    /// Check if an album with the same title and artist already exists in the store.
    static func findDuplicate(
        title: String,
        artist: String,
        in context: ModelContext
    ) -> Album? {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespaces)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespaces)

        guard let albums = try? context.fetch(FetchDescriptor<Album>()) else { return nil }
        return albums.first { album in
            album.title.lowercased().trimmingCharacters(in: .whitespaces) == normalizedTitle &&
            album.artist.lowercased().trimmingCharacters(in: .whitespaces) == normalizedArtist
        }
    }

    /// Find existing album by Apple Music ID or Spotify ID.
    static func findByServiceId(
        appleMusicId: String? = nil,
        spotifyId: String? = nil,
        in context: ModelContext
    ) -> Album? {
        guard let albums = try? context.fetch(FetchDescriptor<Album>()) else { return nil }
        return albums.first { album in
            if let amId = appleMusicId, let existingId = album.appleMusicId, amId == existingId {
                return true
            }
            if let sId = spotifyId, let existingId = album.spotifyId, sId == existingId {
                return true
            }
            return false
        }
    }

    // MARK: - Merge / Update

    /// Merge incoming album data into this existing album.
    /// Fills in missing fields and adds new tracks — never removes user data.
    func mergeFrom(_ incoming: Album) {
        // Fill missing metadata (don't overwrite user edits)
        if artworkURL == nil || artworkURL?.isEmpty == true {
            artworkURL = incoming.artworkURL
        }
        if genre == nil { genre = incoming.genre }
        if releaseYear == nil { releaseYear = incoming.releaseYear }
        if appleMusicId == nil { appleMusicId = incoming.appleMusicId }
        if spotifyId == nil { spotifyId = incoming.spotifyId }

        // Add tracks that don't already exist
        let existingTrackIds = Set(tracks.compactMap(\.appleMusicId))
        let existingTrackTitles = Set(tracks.map { $0.title.lowercased() })

        for incomingTrack in incoming.tracks {
            let isDuplicate: Bool
            if let amId = incomingTrack.appleMusicId {
                isDuplicate = existingTrackIds.contains(amId)
            } else {
                isDuplicate = existingTrackTitles.contains(incomingTrack.title.lowercased())
            }

            if !isDuplicate {
                tracks.append(incomingTrack)
            }
        }

        // Add editions that don't already exist
        let existingEditionIds = Set(editions.compactMap(\.discogsReleaseId))
        for incomingEdition in incoming.editions {
            if let dId = incomingEdition.discogsReleaseId, !existingEditionIds.contains(dId) {
                editions.append(incomingEdition)
            } else if incomingEdition.discogsReleaseId == nil && !editions.contains(where: {
                $0.label == incomingEdition.label && $0.vinylColor == incomingEdition.vinylColor
            }) {
                editions.append(incomingEdition)
            }
        }
    }
}
