import Foundation

/// Local, explainable ranking. No network calls or random changes during rendering.
struct HomeRecommendations {
    let top: [Album]
    let recent: [Album]
    let rediscover: [Album]
    let mix: [Track]
    let discoverySeed: String?

    init(albums: [Album], records: [ListeningRecord], now: Date = .now) {
        let ordered = records.sorted { $0.timestamp > $1.timestamp }
        let lookup = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        recent = Array(ordered.compactMap { record -> Album? in
            guard seen.insert(record.albumId).inserted else { return nil }
            return lookup[record.albumId]
        }.prefix(8))
        var artistScores: [String: Double] = [:]
        var lastPlayed: [UUID: Date] = [:]
        for record in ordered {
            let days = max(0, now.timeIntervalSince(record.timestamp) / 86400)
            // Cap each event so one long/background session cannot dominate forever.
            artistScores[record.artist, default: 0] += min(600, max(0, record.listenDuration)) / (1 + days / 14)
            lastPlayed[record.albumId] = max(lastPlayed[record.albumId] ?? .distantPast, record.timestamp)
        }
        for album in albums where album.tracks.contains(where: \.isFavorite) {
            artistScores[album.artist, default: 0] += 300
        }
        discoverySeed = artistScores.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
            ?? albums.first?.genre ?? albums.first?.artist
        let recentIDs = Set(recent.prefix(3).map(\.id))
        let ranked = albums.sorted {
            let l = artistScores[$0.artist, default: 0], r = artistScores[$1.artist, default: 0]
            return l == r ? $0.id.uuidString < $1.id.uuidString : l > r
        }
        var counts: [String: Int] = [:]
        top = Array(ranked.filter { album in
            guard !recentIDs.contains(album.id), counts[album.artist, default: 0] < 2 else { return false }
            counts[album.artist, default: 0] += 1
            return true
        }.prefix(6))
        let excluded = Set(top.map(\.id)).union(recentIDs)
        rediscover = Array(albums.filter {
            guard !excluded.contains($0.id), let last = lastPlayed[$0.id] else { return false }
            return now.timeIntervalSince(last) >= 14 * 86400
        }.sorted { lastPlayed[$0.id]! < lastPlayed[$1.id]! }.prefix(8))
        var lastTrack: [UUID: Date] = [:]
        for record in ordered {
            if let id = record.trackId { lastTrack[id] = max(lastTrack[id] ?? .distantPast, record.timestamp) }
        }
        let candidates = ranked.flatMap(\.sortedTracks).sorted {
            let l = ($0.isFavorite ? 500.0 : 0) + artistScores[$0.artist, default: 0]
            let r = ($1.isFavorite ? 500.0 : 0) + artistScores[$1.artist, default: 0]
            if l != r { return l > r }
            let ld = lastTrack[$0.id] ?? .distantPast, rd = lastTrack[$1.id] ?? .distantPast
            return ld == rd ? $0.id.uuidString < $1.id.uuidString : ld < rd
        }
        var artists: [String: Int] = [:]
        mix = Array(candidates.filter {
            guard artists[$0.artist, default: 0] < 3 else { return false }
            artists[$0.artist, default: 0] += 1
            return true
        }.prefix(20))
    }
}
