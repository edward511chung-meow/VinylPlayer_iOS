import Foundation
import SwiftData

/// Versioned collection archive. It contains metadata and artwork, never music files or credentials.
nonisolated struct LibraryBackup: Codable, Sendable {
    var version = 1
    var exportedAt = Date()
    var albums: [AlbumData]
    var playlists: [PlaylistData]
    var records: [RecordData]

    nonisolated struct AlbumData: Codable, Sendable {
        let id: UUID
        let title: String
        let artist: String
        let releaseYear: Int?
        let genre: String?
        let colorHex: String
        let selectedEditionId: UUID?
        let enrichmentReceipt: Data?
        let customCoverImageData: Data?
        let appleMusicId: String?
        let spotifyId: String?
        let artworkURL: String?
        let addedDate: Date?
        let tags: [String]
        let customVinylColorHex: String?
        let vinylOpacity: Double?
        let isPinned: Bool
        let tracks: [TrackData]
        let editions: [EditionData]
        @MainActor init(_ value: Album) {
            id = value.id
            title = value.title
            artist = value.artist
            releaseYear = value.releaseYear
            genre = value.genre
            colorHex = value.colorHex
            selectedEditionId = value.selectedEditionId
            enrichmentReceipt = value.enrichmentReceipt
            customCoverImageData = value.customCoverImageData
            appleMusicId = value.appleMusicId
            spotifyId = value.spotifyId
            artworkURL = value.artworkURL
            addedDate = value.addedDate
            tags = value.tags
            customVinylColorHex = value.customVinylColorHex
            vinylOpacity = value.vinylOpacity
            isPinned = value.isPinned
            tracks = value.sortedTracks.map(TrackData.init)
            editions = value.editions.map(EditionData.init)
        }
    }

    nonisolated struct TrackData: Codable, Sendable {
        let id: UUID
        let title: String
        let artist: String
        let albumTitle: String
        let duration: Double
        let trackNumber: Int
        let discNumber: Int
        let side: VinylSide
        let lyrics: String?
        let appleMusicId: String?
        let spotifyURI: String?
        let isFavorite: Bool
        @MainActor init(_ value: Track) {
            id = value.id
            title = value.title
            artist = value.artist
            albumTitle = value.albumTitle
            duration = value.duration
            trackNumber = value.trackNumber
            discNumber = value.discNumber
            side = value.side
            lyrics = value.lyrics
            appleMusicId = value.appleMusicId
            spotifyURI = value.spotifyURI
            isFavorite = value.isFavorite
        }
    }

    nonisolated struct EditionData: Codable, Sendable {
        let id: UUID
        let label: String
        let catalogNumber: String?
        let country: String?
        let year: Int?
        let format: VinylFormat
        let vinylColor: VinylColor
        let coverImageURL: String?
        let notes: String?
        let discogsReleaseId: String?
        let discogsMasterId: String?
        @MainActor init(_ value: VinylEdition) {
            id = value.id
            label = value.label
            catalogNumber = value.catalogNumber
            country = value.country
            year = value.year
            format = value.format
            vinylColor = value.vinylColor
            coverImageURL = value.coverImageURL
            notes = value.notes
            discogsReleaseId = value.discogsReleaseId
            discogsMasterId = value.discogsMasterId
        }
    }

    nonisolated struct PlaylistData: Codable, Sendable {
        let id: UUID
        let name: String
        let createdAt: Date
        var trackIDs: [UUID]
        @MainActor init(_ value: LibraryPlaylist) {
            id = value.id
            name = value.name
            createdAt = value.createdAt
            trackIDs = value.trackIDs
        }
    }

    nonisolated struct RecordData: Codable, Sendable {
        let id: UUID
        let albumId: UUID
        let trackId: UUID?
        let albumTitle: String
        let trackTitle: String?
        let artist: String
        let artworkURL: String?
        let timestamp: Date
        let listenDuration: Double
        @MainActor init(_ value: ListeningRecord) {
            id = value.id
            albumId = value.albumId
            trackId = value.trackId
            albumTitle = value.albumTitle
            trackTitle = value.trackTitle
            artist = value.artist
            artworkURL = value.artworkURL
            timestamp = value.timestamp
            listenDuration = value.listenDuration
        }
    }

    @MainActor static func capture(_ context: ModelContext) throws -> LibraryBackup {
        var backup = LibraryBackup(albums: try context.fetch(FetchDescriptor<Album>()).map(AlbumData.init),
                      playlists: try context.fetch(FetchDescriptor<LibraryPlaylist>()).map(PlaylistData.init),
                      records: try context.fetch(FetchDescriptor<ListeningRecord>()).map(RecordData.init))
        let valid = Set(backup.albums.flatMap(\.tracks).map(\.id))
        for index in backup.playlists.indices { backup.playlists[index].trackIDs.removeAll { !valid.contains($0) } }
        return backup
    }

    func validate() throws {
        guard version == 1 else { throw BackupError.unsupportedVersion }
        let allTracks = albums.flatMap(\.tracks)
        let editions = albums.flatMap(\.editions)
        guard albums.count <= 10_000, allTracks.count <= 200_000, records.count <= 1_000_000,
              Set(albums.map(\.id)).count == albums.count,
              Set(allTracks.map(\.id)).count == allTracks.count,
              Set(editions.map(\.id)).count == editions.count,
              Set(playlists.map(\.id)).count == playlists.count,
              allTracks.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 }),
              records.allSatisfy({ $0.listenDuration.isFinite && $0.listenDuration >= 0 }) else { throw BackupError.invalid }
        let trackIDs = Set(allTracks.map(\.id))
        guard playlists.allSatisfy({ Set($0.trackIDs).isSubset(of: trackIDs) }) else { throw BackupError.invalid }
    }

    /// A separate context makes rollback safe for the user's unsaved UI edits.
    @MainActor func merge(into container: ModelContainer) throws {
        try validate()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            var existingAlbums = try context.fetch(FetchDescriptor<Album>())
            var albumIDs: [UUID: UUID] = [:]
            var trackIDs: [UUID: UUID] = [:]
            for value in albums {
                let existing = existingAlbums.first { $0.id == value.id }
                    ?? existingAlbums.first { $0.title.caseInsensitiveCompare(value.title) == .orderedSame && $0.artist.caseInsensitiveCompare(value.artist) == .orderedSame }
                let album = existing ?? Album(id: value.id, title: value.title, artist: value.artist)
                if existing == nil {
                    album.releaseYear = value.releaseYear
                    album.genre = value.genre
                    album.colorHex = value.colorHex
                    album.enrichmentReceipt = value.enrichmentReceipt
                    album.customCoverImageData = value.customCoverImageData
                    album.appleMusicId = value.appleMusicId
                    album.spotifyId = value.spotifyId
                    album.artworkURL = value.artworkURL
                    album.addedDate = value.addedDate
                    album.tags = value.tags
                    album.customVinylColorHex = value.customVinylColorHex
                    album.vinylOpacity = value.vinylOpacity
                    album.isPinned = value.isPinned
                    context.insert(album); existingAlbums.append(album)
                }
                albumIDs[value.id] = album.id
                for item in value.tracks {
                    let existingTrack = album.tracks.first { $0.id == item.id }
                        ?? album.tracks.first { ($0.appleMusicId != nil && $0.appleMusicId == item.appleMusicId) || ($0.spotifyURI != nil && $0.spotifyURI == item.spotifyURI) || ($0.title == item.title && $0.trackNumber == item.trackNumber && $0.discNumber == item.discNumber) }
                    let track = existingTrack ?? Track(id: item.id, title: item.title, artist: item.artist)
                    if existingTrack == nil {
                        track.albumTitle = item.albumTitle
                        track.duration = item.duration
                        track.trackNumber = item.trackNumber
                        track.discNumber = item.discNumber
                        track.side = item.side
                        track.lyrics = item.lyrics
                        track.appleMusicId = item.appleMusicId
                        track.spotifyURI = item.spotifyURI
                        track.isFavorite = item.isFavorite
                        album.tracks.append(track)
                    } else {
                        track.isFavorite = track.isFavorite || item.isFavorite
                        if track.lyrics == nil { track.lyrics = item.lyrics }
                    }
                    trackIDs[item.id] = track.id
                }
                for item in value.editions where !album.editions.contains(where: { $0.id == item.id }) {
                    let edition = VinylEdition(id: item.id)
                    edition.label = item.label
                    edition.catalogNumber = item.catalogNumber
                    edition.country = item.country
                    edition.year = item.year
                    edition.format = item.format
                    edition.vinylColor = item.vinylColor
                    edition.coverImageURL = item.coverImageURL
                    edition.notes = item.notes
                    edition.discogsReleaseId = item.discogsReleaseId
                    edition.discogsMasterId = item.discogsMasterId
                    album.editions.append(edition)
                }
                if existing == nil { album.selectedEditionId = value.selectedEditionId }
            }
            var existingPlaylists = try context.fetch(FetchDescriptor<LibraryPlaylist>())
            for value in playlists {
                let existing = existingPlaylists.first { $0.id == value.id }
                let playlist = existing ?? LibraryPlaylist(name: value.name)
                if existing == nil {
                    playlist.id = value.id; playlist.createdAt = value.createdAt
                    context.insert(playlist); existingPlaylists.append(playlist)
                }
                var seen = Set(playlist.trackIDs)
                playlist.trackIDs += value.trackIDs.compactMap { trackIDs[$0] }.filter { seen.insert($0).inserted }
            }
            var recordIDs = Set(try context.fetch(FetchDescriptor<ListeningRecord>()).map(\.id))
            for value in records where recordIDs.insert(value.id).inserted {
                context.insert(ListeningRecord(id: value.id, albumId: albumIDs[value.albumId] ?? value.albumId,
                    trackId: value.trackId.map { trackIDs[$0] ?? $0 }, albumTitle: value.albumTitle, trackTitle: value.trackTitle,
                    artist: value.artist, artworkURL: value.artworkURL, timestamp: value.timestamp, listenDuration: value.listenDuration))
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion, invalid, tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return L("backup.version_error")
        case .invalid: return L("backup.invalid")
        case .tooLarge: return L("backup.too_large")
        }
    }
}
