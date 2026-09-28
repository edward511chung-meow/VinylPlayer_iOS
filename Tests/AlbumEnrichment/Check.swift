import Foundation
import SwiftData
import UIKit
func L(_ key: String) -> String { key }

@main struct Check {
    @MainActor static func main() async throws {
        func expect(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); print("PASS: " + label) }
        let raw = #"{"id":"f268b8bc-2768-426b-901b-c7966e76de29","title":"Example","date":"2024-01-01","artist-credit":[{"name":"Artist"}],"media":[{"track-count":1}]}"#
        let candidate = try JSONDecoder().decode(ReleaseCandidate.self, from: Data(raw.utf8))
        expect(EnrichmentMatch.unique([candidate], title: "example", artist: "Artist", count: 1, year: 2024) != nil, "exact unique edition matches")
        expect(EnrichmentMatch.unique([candidate, candidate], title: "Example", artist: "Artist", count: 1, year: nil) == nil, "ambiguous editions rejected")
        expect(EnrichmentMatch.unique([candidate], title: "Example (Live)", artist: "Artist", count: 1, year: nil) == nil, "version labels retained")
        expect(EnrichmentMatch.unique([candidate], title: "Example", artist: "Artist", count: 2, year: nil) == nil, "track count mismatch rejected")
        let container = try ModelContainer(for: Album.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let track = Track(title: "Song", artist: "Artist", duration: 180)
        let album = Album(title: "Example", artist: "Artist", tracks: [track])
        let context = container.mainContext
        context.insert(album); try context.save()
        func picture(_ color: UIColor) -> Data { UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { ctx in color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) } }
        let red = picture(.red), blue = picture(.blue), green = picture(.green)
        try AlbumEnrichment.apply(album: album, cover: red, year: 2024, lyrics: [track.id: "[00:01]Local"], source: "fixture", context: context)
        expect(album.customCoverImageData == red && track.lyrics == "[00:01]Local", "missing artwork and lyrics filled")
        try AlbumEnrichment.apply(album: album, cover: blue, year: 2025, lyrics: [track.id: "Other"], source: "fixture", context: context)
        expect(album.customCoverImageData == red && album.releaseYear == 2024 && track.lyrics == "[00:01]Local", "existing information preserved")
        track.lyrics = "Manual edit"
        try AlbumEnrichment.undo(album, context: context)
        expect(album.customCoverImageData == nil && album.releaseYear == nil && track.lyrics == "Manual edit", "undo preserves later manual lyric edit")
        album.customCoverImageData = red
        try AlbumEnrichment.apply(album: album, cover: blue, source: "fixture", replaceCover: true, context: context)
        try AlbumEnrichment.undo(album, context: context)
        expect(album.customCoverImageData == red, "explicit replacement undo restores original cover")
        try AlbumEnrichment.apply(album: album, cover: blue, source: "fixture", replaceCover: true, context: context)
        album.customCoverImageData = green
        try AlbumEnrichment.apply(album: album, cover: blue, source: "fixture", replaceCover: true, context: context)
        try AlbumEnrichment.undo(album, context: context)
        expect(album.customCoverImageData == green, "new replacement preserves intervening user cover for undo")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try red.write(to: folder.appendingPathComponent("cover.jpg"))
        try "[00:01]Sidecar".write(to: folder.appendingPathComponent("Song.lrc"), atomically: true, encoding: .utf8)
        try "Wrong".write(to: folder.appendingPathComponent("Other.lrc"), atomically: true, encoding: .utf8)
        let result = try await LocalAlbumMetadata.read(folder: folder, tracks: [.init(id: track.id, title: track.title, artist: track.artist, duration: track.duration)])
        expect(result.cover == red && result.lyrics[track.id] == "[00:01]Sidecar", "local cover and matching LRC read")
        expect(result.lyrics.count == 1, "unmatched LRC ignored")
        expect(try! String(contentsOf: folder.appendingPathComponent("Other.lrc"), encoding: .utf8) == "Wrong", "source folder not modified")
        let ambiguous = try await LocalAlbumMetadata.read(folder: folder, tracks: [
            .init(id: track.id, title: "Song", artist: "Artist", duration: 180),
            .init(id: UUID(), title: "Song", artist: "Other Artist", duration: 180)])
        expect(ambiguous.lyrics.isEmpty, "same-title tracks do not share an ambiguous sidecar")
        print("ALL 13 ENRICHMENT CHECKS PASSED")
    }
}
