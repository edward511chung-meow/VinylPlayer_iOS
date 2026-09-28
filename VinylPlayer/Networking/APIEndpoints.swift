import Foundation

enum APIEndpoints {

    // MARK: - Discogs

    enum Discogs {
        /// Search for releases
        static func search(query: String, type: String = "release") -> URL {
            var components = URLComponents(url: APIConfig.Discogs.baseURL.appendingPathComponent("/database/search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "format", value: "Vinyl"),
                URLQueryItem(name: "per_page", value: "25")
            ]
            return components.url!
        }

        /// Get a specific release by ID
        static func release(id: String) -> URL {
            APIConfig.Discogs.baseURL.appendingPathComponent("/releases/\(id)")
        }

        /// Get master release (all versions)
        static func masterRelease(id: String) -> URL {
            APIConfig.Discogs.baseURL.appendingPathComponent("/masters/\(id)")
        }

        /// Get all versions of a master release
        static func masterVersions(id: String, page: Int = 1) -> URL {
            var components = URLComponents(url: APIConfig.Discogs.baseURL.appendingPathComponent("/masters/\(id)/versions"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "format", value: "Vinyl")
            ]
            return components.url!
        }
    }

    // MARK: - Cover Art Archive

    enum CoverArt {
        /// Get cover art for a MusicBrainz release
        static func release(mbid: String) -> URL {
            APIConfig.CoverArtArchive.baseURL.appendingPathComponent("/release/\(mbid)")
        }

        /// Get front cover image directly
        static func frontCover(mbid: String) -> URL {
            APIConfig.CoverArtArchive.baseURL.appendingPathComponent("/release/\(mbid)/front")
        }
    }

    // MARK: - MusicBrainz

    enum MusicBrainz {
        /// Search for releases
        static func searchRelease(query: String) -> URL {
            var components = URLComponents(url: APIConfig.MusicBrainz.baseURL.appendingPathComponent("/release"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: "25")
            ]
            return components.url!
        }
    }
}
