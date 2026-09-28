import Foundation
import SwiftUI
import SwiftData

/// Represents a specific vinyl release/pressing of an album.
@Model
final class VinylEdition {
    var id: UUID
    var label: String
    var catalogNumber: String?
    var country: String?
    var year: Int?
    var format: VinylFormat
    var vinylColor: VinylColor
    var coverImageURL: String?
    var notes: String?

    // Discogs reference
    var discogsReleaseId: String?
    var discogsMasterId: String?

    // Inverse relationship
    var album: Album?

    init(
        id: UUID = UUID(),
        label: String = L("vinyl.unknown"),
        catalogNumber: String? = nil,
        country: String? = nil,
        year: Int? = nil,
        format: VinylFormat = .lp,
        vinylColor: VinylColor = .black,
        coverImageURL: String? = nil,
        notes: String? = nil,
        discogsReleaseId: String? = nil,
        discogsMasterId: String? = nil
    ) {
        self.id = id
        self.label = label
        self.catalogNumber = catalogNumber
        self.country = country
        self.year = year
        self.format = format
        self.vinylColor = vinylColor
        self.coverImageURL = coverImageURL
        self.notes = notes
        self.discogsReleaseId = discogsReleaseId
        self.discogsMasterId = discogsMasterId
    }

    var displayName: String {
        var parts: [String] = []
        if let year { parts.append("\(year)") }
        parts.append(label)
        if let country { parts.append("(\(country))") }
        if vinylColor != .black { parts.append("[\(vinylColor.displayName)]") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Vinyl Format

nonisolated enum VinylFormat: String, Codable, CaseIterable {
    case lp = "LP"
    case single = "7\""
    case ep = "EP"
    case twelve = "12\""
    case pictureDisc = "Picture Disc"

    var rpm: Double {
        switch self {
        case .lp, .ep: return 33.33
        case .single, .twelve, .pictureDisc: return 45.0
        }
    }

    var sizeInches: Int {
        switch self {
        case .lp, .twelve, .pictureDisc: return 12
        case .single: return 7
        case .ep: return 10
        }
    }
}

// MARK: - Vinyl Color

nonisolated enum VinylColor: String, Codable, CaseIterable {
    case black, red, blue, green, white, clear
    case orange, purple, gold, splatter, marbled

    var displayName: String { rawValue.capitalized }

    var colorHex: String {
        switch self {
        case .black:    return "#1A1A1A"
        case .red:      return "#C0392B"
        case .blue:     return "#2980B9"
        case .green:    return "#27AE60"
        case .white:    return "#ECF0F1"
        case .clear:    return "#BDC3C7"
        case .orange:   return "#E67E22"
        case .purple:   return "#8E44AD"
        case .gold:     return "#D4AC0D"
        case .splatter: return "#1A1A1A"
        case .marbled:  return "#1A1A1A"
        }
    }

    var isTranslucent: Bool { self == .clear }

    var discOpacity: Double { isTranslucent ? 0.35 : 1.0 }
}
