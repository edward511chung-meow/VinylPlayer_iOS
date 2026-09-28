import SwiftUI
import SwiftData

/// Listening-based library recommendations plus authenticated catalogue discovery.
/// Imported albums are never presented as new releases.
struct HomeView: View {
    let openCollection: () -> Void
    @Query(sort: \Album.addedDate, order: .reverse) private var albums: [Album]
    @Query(sort: \ListeningRecord.timestamp, order: .reverse) private var records: [ListeningRecord]
    @EnvironmentObject private var styleManager: StyleManager
    @EnvironmentObject private var collectionVM: CollectionViewModel
    @EnvironmentObject private var manager: MusicServiceManager
    @StateObject private var discovery = CatalogSearchModel()
    @State private var discoverySource: MusicSource = .appleMusic
    @State private var discoveryRefresh = 0
    @AppStorage("home.dismissedDiscoveries") private var dismissedDiscoveries = ""
    @State private var selectedAlbum: Album?
    @State private var frames: [String: CGRect] = [:]
    @State private var sourceFrame = CGRect.zero
    @State private var viewportWidth: CGFloat = 393

    private var featureWidth: CGFloat { min(320, max(216, (viewportWidth - 32) * 0.66)) }

    private var recommendations: HomeRecommendations { HomeRecommendations(albums: albums, records: records) }
    private var recent: [Album] { recommendations.recent }
    private var personal: [Album] { recommendations.top }
    private var rediscover: [Album] { recommendations.rediscover }
    private var discoveryKey: String { "\(recommendations.discoverySeed ?? "")|\(discoverySource.rawValue)|\(manager.isAuthorized(discoverySource))|\(discoveryRefresh)" }
    private func identity(_ album: Album) -> String {
        "\(album.title.lowercased())|\(album.artist.lowercased())"
    }
    private var discoveries: [Album] {
        let owned = Set(albums.map(identity))
        let dismissed = Set((try? JSONDecoder().decode([String].self, from: Data(dismissedDiscoveries.utf8))) ?? [])
        var seen = Set<String>()
        return discovery.result.albums.filter { !owned.contains(identity($0)) && !dismissed.contains(identity($0)) && seen.insert(identity($0)).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !albums.isEmpty {
                        if collectionVM.currentTrack != nil { continueListening }
                        if !personal.isEmpty { topPicks }
                        if !recent.isEmpty {
                            shelf(L("home.recent"), albums: Array(recent.prefix(8)), prefix: "recent")
                        }
                        if !recommendations.mix.isEmpty { madeForYou }
                        if !rediscover.isEmpty { shelf(L("home.rediscover"), albums: rediscover, prefix: "rediscover") }
                        discoverSection
                    } else {
                        ContentUnavailableView {
                            Label(L("home.empty"), systemImage: "opticaldisc")
                        } description: {
                            Text(L("home.empty.subtitle"))
                        } actions: {
                            Button(L("home.open_collection"), action: openCollection)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, collectionVM.currentTrack == nil ? 32 : 144)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
            .background(styleManager.theme.backgroundColor)
            .navigationTitle(L("tab.home"))
            .task(id: discoveryKey) {
                if manager.isAuthorized(discoverySource), let seed = recommendations.discoverySeed {
                    await discovery.search(seed, source: discoverySource, manager: manager)
                } else if manager.isAuthorized(.spotify), discoverySource != .spotify { discoverySource = .spotify }
                else if manager.isAuthorized(.appleMusic), discoverySource != .appleMusic { discoverySource = .appleMusic }
            }
            .environment(\.hiddenAlbumFlipSource, selectedAlbum == nil ? nil : activeSource)
            .onPreferenceChange(AlbumFlipFrames.self) { frames = $0 }
            .fullScreenCover(item: $selectedAlbum) { album in
                AlbumFlipPresentation(album: album, sourceFrame: sourceFrame, dismiss: { selectedAlbum = nil }) {
                    AlbumDetailView(album: album, albums: albums)
                }
            }
        }
    }

    @State private var activeSource = ""
    private func open(_ album: Album, source: String) {
        guard let frame = frames[source], frame.width > 0 else { return }
        activeSource = source
        sourceFrame = frame
        updateAlbumFlipPresentation { selectedAlbum = album }
    }

    private var topPicks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("home.top_picks"))
                .font(.title2.bold()).foregroundStyle(styleManager.theme.textPrimary)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(personal.prefix(6))) { album in
                        featuredCard(album)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func featuredCard(_ album: Album) -> some View {
        let source = "home-featured-\(album.id)"
        let reason = album.tracks.contains(where: \.isFavorite) ? L("home.reason_favorite") : (records.isEmpty ? L("home.collection") : L("home.reason_listening"))
        return Button { open(album, source: source) } label: {
            ZStack(alignment: .bottomLeading) {
                AlbumCoverView(album: album, size: featureWidth, height: featureWidth * 1.32,
                               cornerRadius: 0, showsPlaceholderMetadata: false)
                    .overlay {
                        // Blend the same artwork into a soft lower region, without a panel seam.
                        AlbumCoverView(album: album, size: featureWidth, height: featureWidth * 1.32,
                                       cornerRadius: 0, showsPlaceholderMetadata: false)
                            .blur(radius: 16)
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0.4),
                                                       .init(color: .black, location: 0.75)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                    }
                    .overlay(alignment: .top) {
                        // The existing flip animation uses a square artwork source.
                        Color.clear.frame(width: featureWidth, height: featureWidth)
                            .albumFlipSource(source)
                    }
                LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                       .init(color: .black.opacity(0.16), location: 0.6),
                                       .init(color: .black.opacity(0.5), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Text(album.title).font(.headline).lineLimit(2)
                    Text(album.artist).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }.foregroundStyle(.white).padding(16)
            }
            .frame(width: featureWidth, height: featureWidth * 1.32)
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(album.title + ", " + album.artist + ", " + reason)
    }

    private var continueListening: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("home.continue")).font(.title2.bold())
            if let album = collectionVM.currentAlbum, let track = collectionVM.currentTrack {
                HStack(spacing: 16) {
                    AlbumCoverView(album: album, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline).lineLimit(1)
                        Text(album.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        ProgressView(value: collectionVM.playbackProgress)
                    }
                    Button { manager.togglePlayback() } label: {
                        Image(systemName: collectionVM.isPlaying ? "pause.fill" : "play.fill").frame(width: 48, height: 48)
                    }.accessibilityLabel(L(collectionVM.isPlaying ? "playback.pause" : "library.play"))
                }.padding(16).background(.thinMaterial, in: .rect(cornerRadius: 16))
            }
        }
    }

    private var madeForYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("home.for_you")).font(.title2.bold())
                Spacer()
                Button { collectionVM.playTracks(recommendations.mix) } label: { Label(L("library.play"), systemImage: "play.fill") }
            }
            Text(L("home.mix_reason")).font(.caption).foregroundStyle(.secondary)
            ForEach(recommendations.mix.prefix(3)) { track in
                LibraryTrackRow(track: track) { collectionVM.playTracks(recommendations.mix, startingAt: track.id) }
            }
            NavigationLink(L("home.view_mix")) { LibrarySongsView(title: L("home.for_you"), tracks: recommendations.mix) }
        }
        .padding(16).background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("home.discover")).font(.title2.bold())
                Spacer()
                Button { discoveryRefresh += 1 } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("common.retry"))
            }
            Text(L("home.discover_reason")).font(.caption).foregroundStyle(.secondary)
            Picker(L("search.source"), selection: $discoverySource) {
                Text("Apple Music").tag(MusicSource.appleMusic)
                Text("Spotify").tag(MusicSource.spotify)
            }.pickerStyle(.segmented)
            if discovery.isLoading { ProgressView(L("search.loading")) }
            else if !manager.isAuthorized(discoverySource) { Text(L("search.connect_hint")).foregroundStyle(.secondary) }
            else if let error = discovery.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            else if discoveries.isEmpty { Text(L("home.no_discoveries")).foregroundStyle(.secondary) }
            ForEach(discoveries.prefix(6)) { album in
                VStack(alignment: .leading, spacing: 8) {
                    CatalogResultRow(album: album, source: discoverySource)
                    Button(L("home.not_interested")) {
                        var values = (try? JSONDecoder().decode([String].self, from: Data(dismissedDiscoveries.utf8))) ?? []
                        values.append(identity(album))
                        if let data = try? JSONEncoder().encode(Array(Set(values))) { dismissedDiscoveries = String(decoding: data, as: UTF8.self) }
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(.thinMaterial, in: .rect(cornerRadius: 16))
            }
            if !dismissedDiscoveries.isEmpty {
                Button(L("home.reset_discovery")) { dismissedDiscoveries = "" }.font(.caption)
            }
        }
    }

    private func shelf(_ title: String, albums: [Album], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold()).foregroundStyle(styleManager.theme.textPrimary)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(albums) { album in
                        let source = "home-\(prefix)-\(album.id)"
                        Button { open(album, source: source) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                // Anchor only the square cover used by the flip's front face.
                                AlbumCoverView(album: album, size: 144).albumFlipSource(source)
                                Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(album.artist).font(.caption).foregroundStyle(styleManager.theme.textSecondary).lineLimit(1)
                            }.frame(width: 144, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

}
