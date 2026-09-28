import Foundation
import SwiftUI
import SwiftData
import Combine

/// Manages background post-import tasks (lyrics fetch + Apple Music matching).
/// Publishes progress so the UI can show a non-blocking banner.
@MainActor
final class ImportTaskManager: ObservableObject {

    static let shared = ImportTaskManager()
    private init() {}

    enum TaskPhase: Equatable {
        case idle
        case importing(albumTitle: String)           // Just imported
        case fetchingLyrics(albumTitle: String, progress: Double)
        case matchingAppleMusic(albumTitle: String, progress: Double)
        case completed(albumTitle: String, lyricsCount: Int, matchCount: Int)
        case failed(message: String)
    }

    @Published var phase: TaskPhase = .idle
    @Published var isActive = false

    private var currentTask: Task<Void, Never>?
    private var pendingQueue: [(album: Album, isUpdate: Bool, appleMusicService: AppleMusicService?, modelContext: ModelContext)] = []
    private var isProcessing = false

    func startPostImportTasks(
        album: Album,
        isUpdate: Bool,
        appleMusicService: AppleMusicService?,
        modelContext: ModelContext
    ) {
        // Add to queue instead of canceling
        pendingQueue.append((album: album, isUpdate: isUpdate, appleMusicService: appleMusicService, modelContext: modelContext))
        print("[Import] Queued post-import tasks for \(album.title). Queue size: \(pendingQueue.count)")

        // Start processing if not already running
        if !isProcessing {
            processNextInQueue()
        }
    }

    private func processNextInQueue() {
        guard !pendingQueue.isEmpty else {
            // All done
            isProcessing = false
            // Auto-dismiss after 3 seconds
            currentTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.phase = .idle
                self.isActive = false
            }
            return
        }

        isProcessing = true
        let item = pendingQueue.removeFirst()
        let album = item.album
        let appleMusicService = item.appleMusicService
        let modelContext = item.modelContext
        let albumTitle = album.title
        let trackCount = album.tracks.count

        isActive = true
        phase = .importing(albumTitle: albumTitle)

        currentTask = Task { [weak self] in
            guard let self else { return }

            // Phase 0: Download artwork if missing
            if album.customCoverImageData == nil,
               let urlString = album.artworkURL,
               let url = URL(string: urlString) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    album.customCoverImageData = data
                    try? modelContext.save()
                    self.objectWillChange.send()
                    print("[Import] Artwork downloaded for \(albumTitle) (\(data.count) bytes)")
                } catch {
                    print("[Import] Failed to download artwork for \(albumTitle): \(error)")
                }
            }

            // Opt-in enrichment only fills a missing cover when exactly one edition matches.
            if UserDefaults.standard.bool(forKey: "automaticallyFindMissingCovers"),
               album.customCoverImageData == nil, album.artworkURL == nil {
                do {
                    let candidates = try await AlbumMetadataClient.shared.search(title: album.title, artist: album.artist)
                    if let match = EnrichmentMatch.unique(candidates, title: album.title, artist: album.artist, count: album.tracks.count, year: album.releaseYear) {
                        let identities = album.sortedTracks.map { LocalTrackIdentity(id: $0.id, title: $0.title, artist: $0.artist, duration: $0.duration) }
                        guard try await AlbumMetadataClient.shared.verifies(match, tracks: identities) else { throw URLError(.cannotParseResponse) }
                        let cover = try await AlbumMetadataClient.fetch(match.coverURL)
                        try Task.checkCancellation()
                        try AlbumEnrichment.apply(album: album, cover: cover, year: match.year,
                            source: "MusicBrainz / Cover Art Archive · \(match.id)", context: modelContext)
                    }
                } catch { /* A missing cover must never prevent import or lyric lookup. */ }
            }

            // Phase 1: Fetch lyrics
            self.phase = .fetchingLyrics(albumTitle: albumTitle, progress: 0)

            var lyricsCount = 0
            for (index, track) in album.tracks.enumerated() {
                if Task.isCancelled { break }
                if let existing = track.lyrics, !existing.isEmpty { continue }

                let result = await LyricsService.shared.fetchSyncedLyrics(
                    title: track.title,
                    artist: track.artist,
                    albumTitle: track.albumTitle,
                    duration: track.duration > 0 ? track.duration : nil
                )

                // Prefer synced (LRC) lyrics so playback can use them directly;
                // fall back to plain lyrics if synced unavailable.
                if let synced = result?.syncedLyrics, !synced.isEmpty {
                    track.lyrics = synced
                    lyricsCount += 1
                } else if let plain = result?.plainLyrics, !plain.isEmpty {
                    track.lyrics = plain
                    lyricsCount += 1
                }

                let progress = Double(index + 1) / Double(trackCount)
                self.phase = .fetchingLyrics(albumTitle: albumTitle, progress: progress)
            }

            if lyricsCount > 0 {
                try? modelContext.save()
            }

            // Phase 2: Match Apple Music
            var matchCount = 0
            if let appleMusicService, appleMusicService.isAuthorized {
                self.phase = .matchingAppleMusic(albumTitle: albumTitle, progress: 0)

                for (index, track) in album.tracks.enumerated() {
                    if Task.isCancelled { break }
                    if track.appleMusicId != nil {
                        matchCount += 1
                    } else {
                        let matched = await appleMusicService.matchTrack(track)
                        if matched { matchCount += 1 }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }

                    let progress = Double(index + 1) / Double(trackCount)
                    self.phase = .matchingAppleMusic(albumTitle: albumTitle, progress: progress)
                }

                if matchCount > 0 {
                    try? modelContext.save()
                }
            }

            // Phase 3: Completed for this album
            self.phase = .completed(
                albumTitle: albumTitle,
                lyricsCount: lyricsCount,
                matchCount: matchCount
            )

            // Brief pause before processing next album
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            if !Task.isCancelled {
                self.processNextInQueue()
            }
        }
    }

    func dismiss() {
        currentTask?.cancel()
        pendingQueue.removeAll()
        isProcessing = false
        phase = .idle
        isActive = false
    }
}
