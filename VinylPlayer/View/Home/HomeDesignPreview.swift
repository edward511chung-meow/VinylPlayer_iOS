#if DEBUG
import SwiftUI
import SwiftData

/// Isolated, in-memory design data. Never inserted into the user's collection.
struct HomeDesignPreview: View {
    var showsLibrary = false
    var screen = "home"
    private static let previewContainer: ModelContainer = makeContainer()
    private static let headerPreviewContainer: ModelContainer = makeContainer(includesHeaderAlbum: true)
    private var container: ModelContainer { screen == "header" ? Self.headerPreviewContainer : Self.previewContainer }
    @StateObject private var collection = CollectionViewModel()
    @StateObject private var style = StyleManager()
    @StateObject private var music = MusicServiceManager()

    private static func makeContainer(includesHeaderAlbum: Bool = false) -> ModelContainer {
        let container = try! ModelContainer(for: Album.self, ListeningRecord.self, LibraryPlaylist.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let titles = ["Neon Skyline", "Blue Hour", "Paper Moons", "Autumn Letters", "Quiet Noise", "Soft Focus"]
        let artists = ["Luna Echo", "The Satellites", "Mira Lane", "Willow & Pine", "June Arcade", "Luna Echo"]
        let colors = ["#6655DD", "#168DEF", "#18B9BE", "#D69139", "#D95379", "#8567BD"]
        for index in titles.indices {
            let album = Album(title: titles[index], artist: artists[index], releaseYear: 2024 + index % 3,
                              genre: index.isMultiple(of: 2) ? "Alternative" : "Indie Pop", colorHex: colors[index],
                              addedDate: Date().addingTimeInterval(Double(-index * 86400)))
            album.tracks = (1...8).map { Track(title: "Track \($0)", artist: album.artist,
                                               albumTitle: album.title, duration: 180, trackNumber: $0) }
            container.mainContext.insert(album)
            if index < 3 {
                container.mainContext.insert(ListeningRecord(albumId: album.id, albumTitle: album.title,
                    artist: album.artist, timestamp: Date().addingTimeInterval(Double(-index * 3600)),
                    listenDuration: Double(1200 - index * 240)))
            }
        }
        if includesHeaderAlbum {
            // A solid artwork makes any unexpected material across the top safe
            // area obvious, unlike the gradient-only Home placeholders.
            let headerAlbum = Album(title: "Header Check", artist: "Preview", colorHex: "#EF315A")
            headerAlbum.customCoverImageData = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { context in
                UIColor(headerAlbum.color).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            }.pngData()
            headerAlbum.tracks = (1...8).map { Track(title: "Track \($0)", artist: headerAlbum.artist,
                                                    albumTitle: headerAlbum.title, duration: 180, trackNumber: $0) }
            container.mainContext.insert(headerAlbum)
        }
        try? container.mainContext.save()
        return container
    }

    var body: some View {
        Group {
            if screen == "header", let album = try? container.mainContext.fetch(FetchDescriptor<Album>()).first(where: { $0.title == "Header Check" }) {
                AlbumHeaderDesignPreview(album: album)
            }
            else if screen == "panel", let album = try? container.mainContext.fetch(FetchDescriptor<Album>(sortBy: [SortDescriptor(\.title)])).first {
                AlbumFlipPresentation(album: album, sourceFrame: CGRect(x: 32, y: 240, width: 160, height: 160), dismiss: {}) {
                    AlbumDetailView(album: album, albums: [album])
                }.background(Color.gray.opacity(0.2))
            }
            else if screen == "metadata", let album = try? container.mainContext.fetch(FetchDescriptor<Album>()).first {
                AlbumMetadataView(album: album)
            }
            else if screen == "search" { SearchView(initialQuery: "Track 1") }
            else if screen == "backup" { LibraryBackupView() }
            else if screen == "sleep" { SleepTimerView() }
            else if showsLibrary { LibraryView() } else { HomeView {} }
        }
            .modelContainer(container)
            .environmentObject(collection)
            .environmentObject(style)
            .environmentObject(music)
            .tint(style.theme.accentColor)
    }
}

private struct AlbumHeaderDesignPreview: View {
    let album: Album
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationTitle("Header preview")
                .navigationDestination(for: UUID.self) { _ in
                    AlbumDetailView(album: album, albums: [album], usesNativeNavigation: true)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .task {
                    guard path.isEmpty else { return }
                    path.append(album.id)
                }
        }
    }
}

#Preview("Home — Light") { HomeDesignPreview().preferredColorScheme(.light) }
#Preview("Home — Dark") { HomeDesignPreview().preferredColorScheme(.dark) }
#Preview("Album header — Light") { HomeDesignPreview(screen: "header").preferredColorScheme(.light) }
#Preview("Album header — Dark") { HomeDesignPreview(screen: "header").preferredColorScheme(.dark) }
#endif

#if DEBUG
#Preview("Music Library") { HomeDesignPreview(showsLibrary: true) }
#endif

#if DEBUG
#Preview("Search Results") { HomeDesignPreview(screen: "search") }
#Preview("Backup") { HomeDesignPreview(screen: "backup") }
#Preview("Sleep Timer") { HomeDesignPreview(screen: "sleep") }
#endif

#if DEBUG
#Preview("Album Metadata") { HomeDesignPreview(screen: "metadata") }
#endif

#if DEBUG
#Preview("Album panel expansion") { HomeDesignPreview(screen: "panel") }
#endif
