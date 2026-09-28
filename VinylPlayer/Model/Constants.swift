import Foundation

enum AppConstants {

    // MARK: - App Info

    static let appName = "Vinyl Player"
    static let appVersion = "1.0.0"

    // MARK: - App Groups

    static let appGroupId = "group.com.Vinylplayer.shared"

    // MARK: - Turntable

    static let rpm33: Double = 33.33
    static let rpm45: Double = 45.0
    // Top-right pivot geometry: parked on the base-mounted rest, then sweeps
    // naturally from the record's outer groove toward the label.
    static let needleRestAngle: Double = -14
    static let needleStartAngle: Double = -6
    // With the current upper-left pivot geometry, 40° places the stylus just
    // outside the centre label/run-out groove. The full 46° sweep therefore
    // maps the complete playable surface from 0% to 100% progress.
    static let needleEndAngle: Double = 40
    static let vinylGrooveCount: Int = 80

    // MARK: - Animation

    static let flipDuration: Double = 0.6
    static let needleDropDuration: Double = 0.8
    static let vinylSpinUpDuration: Double = 1.2

    // MARK: - Layout

    static let collectionGridSpacing: CGFloat = 12
    static let collectionGridMinSize: CGFloat = 150
    static let turntableVinylRatio: CGFloat = 0.75  // relative to screen width

    // MARK: - API

    enum API {
        static let discogsBaseURL = "https://api.discogs.com"
        static let discogsUserAgent = "VinylPlayer/1.0"
        static let coverArtArchiveBaseURL = "https://coverartarchive.org"
        static let musicBrainzBaseURL = "https://musicbrainz.org/ws/2"
    }

    // MARK: - Storage Keys

    enum StorageKeys {
        static let selectedStyleTheme = "selectedStyleTheme"
        static let preferredRPM = "preferredRPM"
        static let lastPlayedAlbumId = "lastPlayedAlbumId"
        static let lastPlayedTrackId = "lastPlayedTrackId"
        static let hapticIntensity = "hapticIntensity"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let appearanceMode = "appearanceMode"
        static let activeMusicSource = "activeMusicSource"
        static let spotifyAccessToken = "spotify_access_token"
        static let spotifyRefreshToken = "spotify_refresh_token"
        static let spotifyTokenExpiry = "spotify_token_expiry"
        static let lyricsDisplayMode = "lyricsDisplayMode"
        static let turntableBaseStyle = "turntableBaseStyle"
    }
}
