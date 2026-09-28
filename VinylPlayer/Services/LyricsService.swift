import Foundation

/// Resolves lyrics across Lyrimuse sources, with LRCLIB plain-text fallback.
/// Supports both synced (LRC format) and plain lyrics.
final class LyricsService {

    static let shared = LyricsService()
    private init() {}

    // MARK: - Public API

    /// Fetch lyrics for a single track. Returns plain lyrics string, or nil if not found.
    func fetchPlainLyrics(
        title: String,
        artist: String,
        albumTitle: String? = nil,
        duration: TimeInterval? = nil
    ) async -> String? {
        let response = await fetchFromLRCLIB(
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration
        )
        return response?.plainLyrics
    }

    /// Fetch synced lyrics (LRC format) for a single track. Falls back to plain lyrics.
    func fetchSyncedLyrics(
        title: String,
        artist: String,
        albumTitle: String? = nil,
        duration: TimeInterval? = nil
    ) async -> LRCLIBResult? {
        let lines = await LyricSourceResolver().resolve(.init(title: title, artist: artist, album: albumTitle, duration: duration))
        if !lines.isEmpty {
            return LRCLIBResult(syncedLyrics: LyricLine.toLRC(lines), plainLyrics: lines.map(\.text).joined(separator: "\n"))
        }
        return await fetchFromLRCLIB(title: title, artist: artist, albumTitle: albumTitle, duration: duration)
    }

    /// Fetch lyrics for all tracks in an album. Updates each track's `lyrics` property.
    /// Returns the number of tracks that got lyrics.
    @discardableResult
    func fetchLyricsForAlbum(_ album: Album) async -> Int {
        var count = 0

        for track in album.tracks {
            // Skip tracks that already have lyrics
            if let existing = track.lyrics, !existing.isEmpty { continue }

            let result = await fetchSyncedLyrics(
                title: track.title,
                artist: track.artist,
                albumTitle: track.albumTitle,
                duration: track.duration > 0 ? track.duration : nil
            )

            if let synced = result?.syncedLyrics, !synced.isEmpty {
                await MainActor.run {
                    track.lyrics = synced
                }
                count += 1
            } else if let plain = result?.plainLyrics, !plain.isEmpty {
                await MainActor.run {
                    track.lyrics = plain
                }
                count += 1
            }

            // Small delay to avoid hammering the API
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }

        return count
    }

    // MARK: - LRCLIB API

    struct LRCLIBResult {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private func fetchFromLRCLIB(
        title: String,
        artist: String,
        albumTitle: String?,
        duration: TimeInterval?
    ) async -> LRCLIBResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        if let albumTitle, !albumTitle.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: albumTitle))
        }
        if let duration, duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: "\(Int(duration))"))
        }

        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("VinylPlayer/1.0 (https://github.com/vinylplayer)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // 404 = not found, which is normal
                return nil
            }

            struct APIResponse: Decodable {
                let syncedLyrics: String?
                let plainLyrics: String?
            }

            let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
            return LRCLIBResult(
                syncedLyrics: decoded.syncedLyrics,
                plainLyrics: decoded.plainLyrics
            )
        } catch {
            print("LyricsService: failed to fetch lyrics for \"\(title)\" — \(error.localizedDescription)")
            return nil
        }
    }
}
