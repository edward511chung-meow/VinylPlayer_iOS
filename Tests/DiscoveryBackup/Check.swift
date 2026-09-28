import Foundation
import SwiftData
import SwiftUI
func L(_ key: String) -> String { key }

@main struct Check {
    @MainActor static func main() throws {
        func expect(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); print("PASS: " + label) }
        let container = try ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var albums: [Album] = []
        for i in 0..<12 {
            let album = Album(title: "Album \(i)", artist: "Artist \(i % 4)", genre: "Indie",
                tracks: (0..<5).map { Track(title: "Song \(i)-\($0)", artist: "Artist \(i % 4)", duration: 180, trackNumber: $0 + 1) })
            album.tracks[0].isFavorite = i == 3
            album.tracks[0].lyrics = "[00:01]Example"
            album.customCoverImageData = Data([1,2,3,4])
            album.customVinylColorHex = "#FAABCC"
            album.tags = ["Test"]
            album.editions = [VinylEdition(label: "Label", vinylColor: .clear)]
            album.selectedEditionId = album.editions[0].id
            context.insert(album); albums.append(album)
        }
        let records = albums.enumerated().map { i, album in
            ListeningRecord(albumId: album.id, trackId: album.tracks[0].id, albumTitle: album.title, artist: album.artist,
                timestamp: now.addingTimeInterval(-Double(i) * 86400 * 7), listenDuration: 180)
        }
        records.forEach(context.insert)
        let playlist = LibraryPlaylist(name: "Evening")
        playlist.add([albums[4].tracks[2], albums[0].tracks[1]])
        context.insert(playlist)
        try context.save()

        let ranked = HomeRecommendations(albums: albums, records: records, now: now)
        expect(ranked.recent.first?.id == albums[0].id, "recent section follows actual latest history")
        expect(Set(ranked.top.map(\.id)).isDisjoint(with: ranked.recent.prefix(3).map(\.id)), "top picks avoid latest three albums")
        expect(Set(ranked.top.map(\.id)).isDisjoint(with: ranked.rediscover.map(\.id)), "rediscover and top picks do not repeat albums")
        expect(ranked.rediscover.allSatisfy { album in records.contains { $0.albumId == album.id && now.timeIntervalSince($0.timestamp) >= 14*86400 } }, "rediscover only uses previously played older albums")
        expect(Dictionary(grouping: ranked.mix, by: \.artist).values.allSatisfy { $0.count <= 3 }, "mix limits artist domination")
        expect(ranked.mix.contains(where: \.isFavorite), "favorite contributes to mix")
        let empty = HomeRecommendations(albums: [], records: [], now: now)
        expect(empty.mix.isEmpty && empty.top.isEmpty && empty.discoverySeed == nil, "empty library has no invented recommendations")
        expect(HomeRecommendations(albums: albums, records: records, now: now).mix.map(\.id) == ranked.mix.map(\.id), "ranking stays stable during rendering")

        let backup = try LibraryBackup.capture(context)
        let decoded = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(backup))
        try decoded.validate()
        let destination = try ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try decoded.merge(into: destination)
        let restored = try destination.mainContext.fetch(FetchDescriptor<Album>())
        expect(restored.count == albums.count, "backup round trip restores album count")
        let matching = restored.first { $0.id == albums[3].id }!
        expect(matching.tracks.contains(where: \.isFavorite), "backup restores favorites")
        expect(matching.tracks.contains { $0.lyrics == "[00:01]Example" }, "backup restores lyrics")
        expect(matching.customCoverImageData == Data([1,2,3,4]) && matching.customVinylColorHex == "#FAABCC", "backup restores artwork and custom vinyl")
        expect(matching.editions.first?.vinylColor == .clear && matching.selectedEditionId != nil, "backup restores editions and selection")
        expect(try! destination.mainContext.fetch(FetchDescriptor<LibraryPlaylist>()).first!.trackIDs == playlist.trackIDs, "backup keeps playlist order")
        try decoded.merge(into: destination)
        let recheck = ModelContext(destination)
        expect(try! recheck.fetch(FetchDescriptor<Album>()).count == 12, "repeat import does not duplicate albums")
        expect(try! recheck.fetch(FetchDescriptor<Track>()).count == 60, "repeat import does not duplicate songs")
        expect(try! recheck.fetch(FetchDescriptor<ListeningRecord>()).count == 12, "repeat import does not duplicate history")
        var future = decoded; future.version = 999
        do { try future.merge(into: destination); preconditionFailure("future version accepted") } catch { print("PASS: unsupported backup version rejected") }
        var corrupt = decoded; corrupt.albums.append(corrupt.albums[0])
        do { try corrupt.merge(into: destination); preconditionFailure("duplicate IDs accepted") } catch { print("PASS: malformed backup rejected before mutation") }
        expect(try! ModelContext(destination).fetch(FetchDescriptor<Album>()).count == 12, "invalid restore leaves existing collection intact")

        let existingContainer = try ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let existing = Album(title: albums[0].title, artist: albums[0].artist, tracks: [Track(title: albums[0].sortedTracks[1].title, artist: albums[0].artist, trackNumber: 2)])
        let existingID = existing.tracks[0].id
        existingContainer.mainContext.insert(existing); try existingContainer.mainContext.save()
        try decoded.merge(into: existingContainer)
        let mergedPlaylist = try ModelContext(existingContainer).fetch(FetchDescriptor<LibraryPlaylist>()).first!
        expect(mergedPlaylist.trackIDs.contains(existingID), "merge remaps playlist references to existing song IDs")
        expect(try! ModelContext(existingContainer).fetch(FetchDescriptor<Album>()).count == 12, "semantic duplicate album is merged")

        let plan = SleepPlan(deadline: now)
        expect(plan.isExpired(at: now) && !plan.isExpired(at: now.addingTimeInterval(-1)), "sleep deadline expires exactly at boundary")
        expect(!SleepPlan().isActive && !SleepPlan(afterCurrentTrack: true).isExpired(at: now), "cancelled and end-of-track plans do not expire as countdowns")
    }
}
