import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AlbumMetadataView: View {
    @Bindable var album: Album
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("automaticallyFindMissingCovers") private var autoCovers = false
    @State private var title = ""
    @State private var artist = ""
    @State private var candidates: [ReleaseCandidate] = []
    @State private var searched = false
    @State private var busy = false
    @State private var message: String?
    @State private var importing = false
    @State private var replaceCover = false
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("metadata.hint")).foregroundStyle(.secondary)
                    Toggle(L("metadata.auto"), isOn: $autoCovers)
                    Button(L("metadata.local"), systemImage: "folder") { importing = true }
                    Button(L("metadata.fill"), systemImage: "sparkles") { run { try await fill() } }
                }
                Section(L("metadata.match")) {
                    TextField(L("album.title_placeholder"), text: $title)
                    TextField(L("album.artist_placeholder"), text: $artist)
                    Button(L("metadata.search"), systemImage: "magnifyingglass") { run { try await search() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || artist.trimmingCharacters(in: .whitespaces).isEmpty)
                    Toggle(L("metadata.replace"), isOn: $replaceCover)
                }
                if let log = AlbumEnrichment.receipt(album) {
                    Section(L("metadata.source")) {
                        Text(log.source).font(.caption)
                        Button(L("metadata.undo"), role: .destructive) { run { try AlbumEnrichment.undo(album, context: context); message = L("metadata.restored") } }
                    }
                }
                if searched {
                    Section(L("metadata.candidates")) {
                        if candidates.isEmpty { Text(L("metadata.no_results")) }
                        ForEach(candidates) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    AsyncImage(url: item.coverURL) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "opticaldisc").foregroundStyle(.secondary) }.frame(width: 64, height: 64)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.headline)
                                        Text(item.artist)
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: 16) {
                                    Button(L("metadata.use")) { run { try await apply(item, replace: replaceCover); message = L("metadata.applied") } }.buttonStyle(.bordered)
                                    Link("MusicBrainz", destination: URL(string: "https://musicbrainz.org/release/\(item.id)")!).font(.caption)
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
                Section { Text(L("metadata.local_hint")).font(.caption).foregroundStyle(.secondary) }
            }
            .disabled(busy)
            .safeAreaInset(edge: .bottom) {
                if busy || message != nil {
                    HStack(spacing: 12) {
                        if busy { ProgressView(); Text(L("metadata.working")); Spacer(); Button(L("common.cancel")) { operation?.cancel() } }
                        else if let message { Text(message).font(.callout) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                }
            }
            .navigationTitle(L("metadata.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } } }
        }
        .onAppear { title = album.title; artist = album.artist }
        .onDisappear { operation?.cancel() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): run {
                let identities = album.tracks.map { LocalTrackIdentity(id: $0.id, title: $0.title, artist: $0.artist, duration: $0.duration) }
                let result = try await LocalAlbumMetadata.read(folder: url, tracks: identities)
                try Task.checkCancellation()
                try AlbumEnrichment.apply(album: album, cover: result.cover, lyrics: result.lyrics, source: L("metadata.local_source"), context: context)
                message = L("metadata.local_done")
            }
            case .failure(let error): message = error.localizedDescription
            }
        }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do { try await work() } catch is CancellationError { message = nil } catch { message = error.localizedDescription }
        }
    }
    private func search() async throws {
        candidates = try await AlbumMetadataClient.shared.search(title: title, artist: artist)
        try Task.checkCancellation(); searched = true
    }
    private func apply(_ item: ReleaseCandidate, replace: Bool) async throws {
        var cover: Data?
        if replace || (album.customCoverImageData == nil && album.artworkURL == nil) {
            cover = try await AlbumMetadataClient.fetch(item.coverURL)
            guard let cover, UIImage(data: cover) != nil else { throw URLError(.cannotDecodeContentData) }
        }
        try Task.checkCancellation()
        try AlbumEnrichment.apply(album: album, cover: cover, year: item.year, source: "MusicBrainz / Cover Art Archive · \(item.id)", replaceCover: replace, context: context)
    }
    private func fill() async throws {
        var needsChoice = false
        var artworkError: String?
        do {
            if album.customCoverImageData == nil && album.artworkURL == nil {
                try await search()
                if let match = EnrichmentMatch.unique(candidates, title: album.title, artist: album.artist, count: album.tracks.count, year: album.releaseYear) {
                    let identities = album.sortedTracks.map { LocalTrackIdentity(id: $0.id, title: $0.title, artist: $0.artist, duration: $0.duration) }
                    if try await AlbumMetadataClient.shared.verifies(match, tracks: identities) {
                        try await apply(match, replace: false)
                    } else { needsChoice = true }
                } else { needsChoice = !candidates.isEmpty }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { artworkError = error.localizedDescription }
        var lyrics: [UUID: String] = [:]
        for track in album.sortedTracks where (track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try Task.checkCancellation()
            let result = await LyricsService.shared.fetchSyncedLyrics(title: track.title, artist: track.artist, albumTitle: album.title, duration: track.duration > 0 ? track.duration : nil)
            if let text = result?.syncedLyrics ?? result?.plainLyrics, !text.isEmpty { lyrics[track.id] = text }
        }
        try Task.checkCancellation()
        if !lyrics.isEmpty { try AlbumEnrichment.apply(album: album, lyrics: lyrics, source: "LyricsService", context: context) }
        message = needsChoice ? L("metadata.choose") : L("metadata.complete", lyrics.count)
        if let artworkError { message = (message ?? "") + "\n" + artworkError }
    }
}
