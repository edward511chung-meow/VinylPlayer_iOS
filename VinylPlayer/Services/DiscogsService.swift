import Foundation
import Combine

/// Discogs API integration for searching vinyl records, fetching release details,
/// importing artwork and edition metadata.
///
/// Uses the existing APIClient + APIEndpoints + DiscogsModels.
/// Adds higher-level methods that return app-domain types (Album, VinylEdition).
final class DiscogsService: ObservableObject {

    static let shared = DiscogsService()

    @Published var isSearching = false

    private let client = APIClient.shared

    private var headers: [String: String] {
        var h: [String: String] = [
            "User-Agent": APIConfig.Discogs.userAgent
        ]
        let token = APIConfig.Discogs.personalAccessToken
        if !token.isEmpty {
            h["Authorization"] = "Discogs token=\(token)"
        }
        return h
    }

    // MARK: - Search

    /// Search Discogs for vinyl releases matching a query.
    func searchReleases(query: String) async throws -> [DiscogsSearchResult] {
        isSearching = true
        defer { isSearching = false }

        let url = APIEndpoints.Discogs.search(query: query)
        let response: DiscogsSearchResponse = try await client.request(
            url: url,
            headers: headers
        )
        return response.results
    }

    /// Search by barcode (UPC/EAN).
    func searchByBarcode(_ barcode: String) async throws -> [DiscogsSearchResult] {
        var components = URLComponents(url: APIConfig.Discogs.baseURL.appendingPathComponent("/database/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "barcode", value: barcode),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "format", value: "Vinyl")
        ]

        let response: DiscogsSearchResponse = try await client.request(
            url: components.url!,
            headers: headers
        )
        return response.results
    }

    // MARK: - Release Details

    /// Fetch full release details from Discogs.
    func fetchRelease(id: String) async throws -> DiscogsRelease {
        let url = APIEndpoints.Discogs.release(id: id)
        return try await client.request(url: url, headers: headers)
    }

    /// Fetch all vinyl versions of a master release.
    func fetchMasterVersions(masterId: String, page: Int = 1) async throws -> DiscogsMasterVersionsResponse {
        let url = APIEndpoints.Discogs.masterVersions(id: masterId, page: page)
        return try await client.request(url: url, headers: headers)
    }

    // MARK: - Image Fetching

    /// Download cover art image data from a Discogs image URL.
    func fetchCoverImage(url: String) async throws -> Data {
        guard let imageURL = URL(string: url) else {
            throw APIError.invalidURL
        }
        return try await client.fetchData(url: imageURL, headers: headers)
    }

    // MARK: - Conversion to App Models

    /// Convert a Discogs release into an Album with editions.
    func convertToAlbum(release: DiscogsRelease) -> Album {
        let artist = release.artists?.first?.name
            .replacingOccurrences(of: " (\\d+)", with: "", options: .regularExpression)
            ?? "Unknown"

        let tracks = (release.tracklist ?? []).compactMap { discogsTrack -> Track? in
            // Skip headings (position is empty or non-standard)
            guard let position = discogsTrack.position, !position.isEmpty else { return nil }

            let side: VinylSide = {
                let p = position.uppercased()
                if p.hasPrefix("A") { return .a }
                if p.hasPrefix("B") { return .b }
                if p.hasPrefix("C") { return .c }
                if p.hasPrefix("D") { return .d }
                // Numeric: split evenly
                if let num = Int(p) {
                    let total = release.tracklist?.count ?? 1
                    return num <= (total / 2 + 1) ? .a : .b
                }
                return .a
            }()

            let trackNum: Int = {
                let p = position.uppercased()
                // "A1" -> 1, "B3" -> 3, "1" -> 1
                let digits = p.filter(\.isNumber)
                return Int(digits) ?? 1
            }()

            return Track(
                title: discogsTrack.title,
                artist: artist,
                albumTitle: release.title,
                duration: parseDuration(discogsTrack.duration),
                trackNumber: trackNum,
                side: side
            )
        }

        let edition = convertToEdition(release: release)

        return Album(
            title: release.title,
            artist: artist,
            releaseYear: release.year,
            genre: release.genres?.first,
            colorHex: "#1A1A1A",
            tracks: tracks,
            editions: [edition],
            selectedEditionId: edition.id,
            artworkURL: release.images?.first(where: { $0.type == "primary" })?.uri
                ?? release.images?.first?.uri
        )
    }

    /// Convert a Discogs release into a VinylEdition.
    func convertToEdition(release: DiscogsRelease) -> VinylEdition {
        let label = release.labels?.first?.name ?? "Unknown"
        let catno = release.labels?.first?.catno

        // Try to detect vinyl color from format descriptions
        let vinylColor = detectVinylColor(from: release.formats)

        return VinylEdition(
            label: label,
            catalogNumber: catno,
            country: release.country,
            year: release.year,
            format: detectFormat(from: release.formats),
            vinylColor: vinylColor,
            coverImageURL: release.images?.first(where: { $0.type == "primary" })?.uri
                ?? release.images?.first?.uri,
            notes: release.notes,
            discogsReleaseId: String(release.id),
            discogsMasterId: release.masterId.map { String($0) }
        )
    }

    /// Convert a search result into a lightweight Album (no tracks).
    func convertSearchResultToAlbum(_ result: DiscogsSearchResult) -> Album {
        let titleParts = result.title.components(separatedBy: " - ")
        let artist = titleParts.count > 1 ? titleParts[0].trimmingCharacters(in: .whitespaces) : "Unknown"
        let title = titleParts.count > 1
            ? titleParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            : result.title

        return Album(
            title: title,
            artist: artist,
            releaseYear: result.year.flatMap { Int($0) },
            genre: result.genre?.first,
            colorHex: "#1A1A1A",
            artworkURL: result.coverImage ?? result.thumb
        )
    }

    // MARK: - Helpers

    private func parseDuration(_ str: String?) -> TimeInterval {
        guard let str, !str.isEmpty else { return 0 }
        let parts = str.components(separatedBy: ":")
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            return m * 60 + s
        }
        return 0
    }

    private func detectVinylColor(from formats: [DiscogsFormat]?) -> VinylColor {
        guard let formats else { return .black }

        let descriptions = formats
            .compactMap(\.descriptions)
            .flatMap { $0 }
            .map { $0.lowercased() }

        for desc in descriptions {
            if desc.contains("clear") || desc.contains("transparent") { return .clear }
            if desc.contains("red") { return .red }
            if desc.contains("blue") { return .blue }
            if desc.contains("green") { return .green }
            if desc.contains("white") { return .white }
            if desc.contains("orange") { return .orange }
            if desc.contains("purple") || desc.contains("violet") { return .purple }
            if desc.contains("gold") || desc.contains("yellow") { return .gold }
            if desc.contains("splatter") || desc.contains("splash") { return .splatter }
            if desc.contains("marble") || desc.contains("swirl") { return .marbled }
        }

        return .black
    }

    private func detectFormat(from formats: [DiscogsFormat]?) -> VinylFormat {
        guard let formats else { return .lp }

        let descriptions = formats
            .compactMap(\.descriptions)
            .flatMap { $0 }
            .map { $0.lowercased() }

        let names = formats.map { $0.name.lowercased() }

        if names.contains("vinyl") || descriptions.contains("lp") || descriptions.contains("album") {
            if descriptions.contains(where: { $0.contains("7\"") || $0.contains("single") }) {
                return .single
            }
            if descriptions.contains(where: { $0.contains("10\"") || $0.contains("ep") }) {
                return .ep
            }
            if descriptions.contains(where: { $0.contains("12\"") && ($0.contains("single") || $0.contains("maxi")) }) {
                return .twelve
            }
            if descriptions.contains(where: { $0.contains("picture disc") }) {
                return .pictureDisc
            }
        }

        return .lp
    }
}
