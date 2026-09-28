import Foundation

enum APIConfig {

    // MARK: - Discogs

    enum Discogs {
        static let baseURL = URL(string: "https://api.discogs.com")!
        static let userAgent = "VinylPlayer/1.0 +https://github.com/vinylplayer"
        // User needs to register at https://www.discogs.com/settings/developers
        // to get their own key & secret
        static var consumerKey: String { "" }
        static var consumerSecret: String { "" }
        static var personalAccessToken: String { "" }
    }

    // MARK: - Cover Art Archive (free, no auth)

    enum CoverArtArchive {
        static let baseURL = URL(string: "https://coverartarchive.org")!
    }

    // MARK: - MusicBrainz (free, no auth, rate-limited to 1req/sec)

    enum MusicBrainz {
        static let baseURL = URL(string: "https://musicbrainz.org/ws/2")!
        static let userAgent = "VinylPlayer/1.0 (madmadmobileai@gmail.com)"
    }

    // MARK: - Apple Music

    enum AppleMusic {
        // Set via MusicKit — no manual key needed for device-level access
        static let storefront = "us"
    }

    // MARK: - Spotify

    enum Spotify {
        static let clientId = "735c3b0ccf2c4c3aaeb3969d60217235"
        static let redirectURI = "vinylplayer://spotify-callback"
        static let scopes = [
            "user-read-playback-state",
            "user-modify-playback-state",
            "user-read-currently-playing",
            "streaming",
            "user-library-read"
        ]
    }
}
