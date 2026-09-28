import Foundation
import UIKit
import SwiftData

nonisolated struct ReleaseCandidate: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: String?
    let country: String?
    let disambiguation: String?
    let artistCredit: [Credit]?
    let media: [Medium]?
    nonisolated struct Credit: Decodable, Sendable { let name: String? }
    nonisolated struct Medium: Decodable, Sendable {
        let trackCount: Int?
        enum CodingKeys: String, CodingKey { case trackCount = "track-count" }
    }
    enum CodingKeys: String, CodingKey {
        case id, title, date, country, disambiguation, media
        case artistCredit = "artist-credit"
    }
    var artist: String { artistCredit?.compactMap(\.name).joined(separator: ", ") ?? "" }
    var count: Int { media?.compactMap(\.trackCount).reduce(0, +) ?? 0 }
    var year: Int? { date.flatMap { Int($0.prefix(4)) } }
    var detail: String { [date, country, disambiguation, count > 0 ? "\(count) tracks" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    var coverURL: URL { URL(string: "https://coverartarchive.org/release/\(id)/front-500")! }
}

nonisolated enum EnrichmentMatch {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    // Preserve version labels and punctuation; ambiguity is preferable to the wrong edition.
    static func unique(_ candidates: [ReleaseCandidate], title: String, artist: String, count: Int, year: Int?) -> ReleaseCandidate? {
        let matches = candidates.filter {
            normalized($0.title) == normalized(title) && normalized($0.artist) == normalized(artist)
                && count > 0 && $0.count == count && (year == nil || $0.year == year)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

actor AlbumMetadataClient {
    static let shared = AlbumMetadataClient()
    private var nextRequest = Date.distantPast
    private func waitForSlot() async throws {
        let slot = max(Date(), nextRequest)
        nextRequest = slot.addingTimeInterval(1.1)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
    }
    private var cache: [String: [ReleaseCandidate]] = [:]
    func search(title: String, artist: String) async throws -> [ReleaseCandidate] {
        let key = title + "|" + artist
        if let cached = cache[key] { return cached }
        try await waitForSlot()
        func escaped(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        url.queryItems = [.init(name: "query", value: "release:\"\(escaped(title))\" AND artist:\"\(escaped(artist))\""), .init(name: "fmt", value: "json"), .init(name: "limit", value: "25")]
        let data = try await Self.fetch(url.url!)
        struct Response: Decodable { let releases: [ReleaseCandidate] }
        let result = try JSONDecoder().decode(Response.self, from: data).releases.filter { UUID(uuidString: $0.id) != nil }
        cache[key] = result
        return result
    }
    func verifies(_ candidate: ReleaseCandidate, tracks: [LocalTrackIdentity]) async throws -> Bool {
        try await waitForSlot()
        let url = URL(string: "https://musicbrainz.org/ws/2/release/\(candidate.id)?inc=recordings&fmt=json")!
        let data = try await Self.fetch(url)
        struct Release: Decodable {
            struct Medium: Decodable {
                struct Song: Decodable { let title: String; let length: Int? }
                let tracks: [Song]?
            }
            let media: [Medium]
        }
        let songs = try JSONDecoder().decode(Release.self, from: data).media.flatMap { $0.tracks ?? [] }
        guard !tracks.isEmpty, songs.count == tracks.count else { return false }
        return zip(songs, tracks).allSatisfy { song, track in
            EnrichmentMatch.normalized(song.title) == EnrichmentMatch.normalized(track.title)
                && (track.duration <= 0 || song.length.map { abs(Double($0) / 1000 - track.duration) <= 2 } == true)
        }
    }
    nonisolated static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("VinylPlayer/1.0 (iOS album metadata)", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 12_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        try Task.checkCancellation()
        return try Data(contentsOf: temporary)
    }
}

/// Stores original values and only reverses fields that still equal our applied values.
/// A later user edit must never be overwritten by Undo.
nonisolated struct EnrichmentReceipt: Codable {
    var source: String
    var previousCover: Data?
    var appliedCover: Data?
    var previousYear: Int?
    var appliedYear: Int?
    var lyrics: [String: String] = [:]
    var previousLyrics: [String: String] = [:]
}

@MainActor enum AlbumEnrichment {
    static func receipt(_ album: Album) -> EnrichmentReceipt? {
        album.enrichmentReceipt.flatMap { try? JSONDecoder().decode(EnrichmentReceipt.self, from: $0) }
    }
    static func apply(album: Album, cover: Data? = nil, year: Int? = nil, lyrics: [UUID: String] = [:], source: String, replaceCover: Bool = false, context: ModelContext) throws {
        let oldCover = album.customCoverImageData, oldYear = album.releaseYear, oldReceipt = album.enrichmentReceipt
        let oldLyrics = Dictionary(uniqueKeysWithValues: album.tracks.map { ($0.id, $0.lyrics) })
        var log = receipt(album) ?? EnrichmentReceipt(source: source, previousCover: oldCover, previousYear: oldYear)
        var changed = false
        if !log.source.contains(source) { log.source += " · " + source }
        if let cover, UIImage(data: cover) != nil, replaceCover || (album.customCoverImageData == nil && album.artworkURL == nil) {
            if log.appliedCover != oldCover { log.previousCover = oldCover }
            album.customCoverImageData = cover; log.appliedCover = cover; changed = true
        }
        if album.releaseYear == nil, let year { album.releaseYear = year; log.appliedYear = year; changed = true }
        for track in album.tracks where (track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let text = lyrics[track.id], !text.isEmpty {
                if let original = track.lyrics { log.previousLyrics[track.id.uuidString] = original }
                track.lyrics = text; log.lyrics[track.id.uuidString] = text; changed = true
            }
        }
        guard changed else { return }
        do { album.enrichmentReceipt = try JSONEncoder().encode(log); try context.save() }
        catch {
            album.customCoverImageData = oldCover; album.releaseYear = oldYear; album.enrichmentReceipt = oldReceipt
            for track in album.tracks { track.lyrics = oldLyrics[track.id] ?? nil }
            throw error
        }
    }
    static func undo(_ album: Album, context: ModelContext) throws {
        guard let log = receipt(album) else { return }
        let cover = album.customCoverImageData, year = album.releaseYear, raw = album.enrichmentReceipt
        let lyrics = Dictionary(uniqueKeysWithValues: album.tracks.map { ($0.id, $0.lyrics) })
        if let applied = log.appliedCover, album.customCoverImageData == applied { album.customCoverImageData = log.previousCover }
        if let applied = log.appliedYear, album.releaseYear == applied { album.releaseYear = log.previousYear }
        for track in album.tracks where log.lyrics[track.id.uuidString] != nil && track.lyrics == log.lyrics[track.id.uuidString] { track.lyrics = log.previousLyrics[track.id.uuidString] }
        album.enrichmentReceipt = nil
        do { try context.save() } catch {
            album.customCoverImageData = cover; album.releaseYear = year; album.enrichmentReceipt = raw
            for track in album.tracks { track.lyrics = lyrics[track.id] ?? nil }
            throw error
        }
    }
}
