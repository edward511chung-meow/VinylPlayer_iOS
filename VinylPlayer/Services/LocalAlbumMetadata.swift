import AVFoundation
import Foundation

nonisolated struct LocalMetadataResult: Sendable {
    var cover: Data?
    var lyrics: [UUID: String] = [:]
}
nonisolated struct LocalTrackIdentity: Sendable {
    let id: UUID
    let title: String
    let artist: String
    let duration: Double
}

/// Reads one explicitly selected album directory. Never writes or recursively scans the NAS.
nonisolated enum LocalAlbumMetadata {
    static func read(folder: URL, tracks: [LocalTrackIdentity]) async throws -> LocalMetadataResult {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        var result = LocalMetadataResult()
        for name in ["cover.jpg", "folder.jpg", "cover.png", "folder.png"] {
            if let url = files.first(where: { $0.lastPathComponent.lowercased() == name }), let data = try? boundedData(url, limit: 12_000_000) { result.cover = data; break }
        }
        for track in tracks {
            try Task.checkCancellation()
            guard tracks.filter({ EnrichmentMatch.normalized($0.title) == EnrichmentMatch.normalized(track.title) }).count == 1 else { continue }
            let sidecars = files.filter { $0.pathExtension.lowercased() == "lrc" && EnrichmentMatch.normalized($0.deletingPathExtension().lastPathComponent) == EnrichmentMatch.normalized(track.title) }
            if sidecars.count == 1, let data = try? boundedData(sidecars[0], limit: 2_000_000), let text = String(data: data, encoding: .utf8), !text.isEmpty { result.lyrics[track.id] = text }
        }
        let audio = files.filter { ["mp3", "m4a", "aac", "flac", "aif", "aiff", "wav", "alac"].contains($0.pathExtension.lowercased()) }
        for url in audio.prefix(200) {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard let metadata = try? await asset.load(.commonMetadata) else { continue }
            var title: String?, artist: String?, cover: Data?
            for item in metadata {
                switch item.commonKey {
                case .commonKeyTitle: title = try? await item.load(.stringValue)
                case .commonKeyArtist: artist = try? await item.load(.stringValue)
                case .commonKeyArtwork: cover = try? await item.load(.dataValue)
                default: break
                }
            }
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            let name = title ?? url.deletingPathExtension().lastPathComponent
            let matches = tracks.filter { EnrichmentMatch.normalized($0.title) == EnrichmentMatch.normalized(name) && (artist == nil || EnrichmentMatch.normalized($0.artist) == EnrichmentMatch.normalized(artist!)) && ($0.duration <= 0 || duration <= 0 || abs($0.duration - duration) <= 2) }
            guard matches.count == 1 else { continue }
            if let cover, cover.count <= 12_000_000 { result.cover = cover }
            let track = matches[0]
            let sidecar = files.first { $0.pathExtension.lowercased() == "lrc" && $0.deletingPathExtension().lastPathComponent == url.deletingPathExtension().lastPathComponent }
            if result.lyrics[track.id] == nil, let sidecar, let data = try? boundedData(sidecar, limit: 2_000_000) { result.lyrics[track.id] = String(data: data, encoding: .utf8) }
            if let metadata = try? await asset.load(.metadata) {
                for item in metadata where item.identifier == .id3MetadataUnsynchronizedLyric || item.identifier == .iTunesMetadataLyrics {
                    if let text = try? await item.load(.stringValue), !text.isEmpty { result.lyrics[track.id] = text; break }
                }
            }
        }
        return result
    }
    static func boundedData(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        return try Data(contentsOf: url)
    }
}
