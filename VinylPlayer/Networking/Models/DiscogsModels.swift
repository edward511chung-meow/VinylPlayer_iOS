import Foundation

/// Discogs API response models

// MARK: - Search

struct DiscogsSearchResponse: Codable {
    let pagination: DiscogsPagination
    let results: [DiscogsSearchResult]
}

struct DiscogsPagination: Codable {
    let page: Int
    let pages: Int
    let perPage: Int
    let items: Int
}

struct DiscogsSearchResult: Codable, Identifiable {
    let id: Int
    let type: String?
    let masterId: Int?
    let masterUrl: String?
    let title: String
    let country: String?
    let year: String?
    let format: [String]?
    let label: [String]?
    let genre: [String]?
    let style: [String]?
    let thumb: String?       // Thumbnail URL
    let coverImage: String?  // Full cover URL
    let resourceUrl: String?
    let catno: String?       // Catalog number
}

// MARK: - Release Detail

struct DiscogsRelease: Codable {
    let id: Int
    let title: String
    let artists: [DiscogsArtist]?
    let year: Int?
    let country: String?
    let labels: [DiscogsLabel]?
    let formats: [DiscogsFormat]?
    let genres: [String]?
    let styles: [String]?
    let tracklist: [DiscogsTrack]?
    let images: [DiscogsImage]?
    let notes: String?
    let masterId: Int?
}

struct DiscogsArtist: Codable {
    let name: String
    let id: Int?
    let resourceUrl: String?
}

struct DiscogsLabel: Codable {
    let name: String
    let catno: String?
    let id: Int?
}

struct DiscogsFormat: Codable {
    let name: String        // "Vinyl", "LP", etc.
    let qty: String?
    let descriptions: [String]?
}

struct DiscogsTrack: Codable {
    let position: String?   // "A1", "B2", etc.
    let title: String
    let duration: String?   // "3:45"
}

struct DiscogsImage: Codable {
    let type: String         // "primary" or "secondary"
    let uri: String
    let resourceUrl: String?
    let width: Int?
    let height: Int?
}

// MARK: - Master Versions

struct DiscogsMasterVersionsResponse: Codable {
    let pagination: DiscogsPagination
    let versions: [DiscogsVersion]
}

struct DiscogsVersion: Codable, Identifiable {
    let id: Int
    let title: String
    let country: String?
    let year: String?
    let label: String?
    let catno: String?
    let format: String?
    let thumb: String?
    let resourceUrl: String?
}
