import Foundation
import SwiftData

/// Ordered references keep playlist deletion independent of album ownership.
@Model
final class LibraryPlaylist {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var trackIDs: [UUID] = []

    init(name: String) { self.name = name }

    func tracks(in library: [Track]) -> [Track] {
        let lookup = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return trackIDs.compactMap { lookup[$0] }
    }

    func add(_ tracks: [Track]) {
        var seen = Set(trackIDs)
        trackIDs.append(contentsOf: tracks.filter { seen.insert($0.id).inserted }.map(\.id))
    }
}
