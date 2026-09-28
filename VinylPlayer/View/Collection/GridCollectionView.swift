import SwiftUI
import SwiftData
import UIKit

// MARK: - Filter Option

private struct FilterOption: Identifiable {
    enum FilterType { case all, genre, decade, tag }

    let label: String
    let type: FilterType
    var value: Int? = nil  // used for decade

    var id: String { "\(type)-\(label)" }
}

// MARK: - Section Index Item

private struct SectionItem: Identifiable {
    let key: String       // ID for ScrollViewReader
    let shortLabel: String // Displayed in the scrubber
    var id: String { key }
}

private enum FanInteractionPhase {
    case indexing
    case settling
    case focused
}

private struct SectionHeaderPositionsKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Keeps the presented album and its transition source in one state update.
/// If these are stored separately, the cover can be presented before SwiftUI
/// has propagated the new source ID, so the first zoom has no matching source.
private struct AlbumHeroPresentation: Identifiable {
    let album: Album
    let sourceID: String
    let frame: CGRect

    var id: String { sourceID }
}

/// UIKit's native menu button keeps the system UIMenu presentation while also
/// honouring the background color of an iOS 26 prominent-glass configuration.
/// SwiftUI's toolbar Menu currently drops that configured tint.
private struct NativeTintedMenuButton: UIViewRepresentable {
    let accentColor: Color
    let accessibilityLabel: String
    let searchDiscogsTitle: String
    let importMusicTitle: String
    let searchDiscogs: () -> Void
    let importMusic: () -> Void

    final class Coordinator {
        var searchDiscogs: () -> Void
        var importMusic: () -> Void

        init(searchDiscogs: @escaping () -> Void, importMusic: @escaping () -> Void) {
            self.searchDiscogs = searchDiscogs
            self.importMusic = importMusic
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(searchDiscogs: searchDiscogs, importMusic: importMusic)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(configuration: buttonConfiguration)
        button.tintColor = .white
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = accessibilityLabel
        button.menu = makeMenu(coordinator: context.coordinator)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.searchDiscogs = searchDiscogs
        context.coordinator.importMusic = importMusic
        button.configuration = buttonConfiguration
        button.accessibilityLabel = accessibilityLabel
        button.menu = makeMenu(coordinator: context.coordinator)
    }

    private var buttonConfiguration: UIButton.Configuration {
        var configuration = UIButton.Configuration.prominentGlass()
        configuration.image = UIImage(systemName: "plus")?.withTintColor(
            .white,
            renderingMode: .alwaysOriginal
        )
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor(accentColor)
        configuration.cornerStyle = .capsule
        configuration.indicator = .none
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: 10,
            bottom: 10,
            trailing: 10
        )
        return configuration
    }

    private func makeMenu(coordinator: Coordinator) -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: searchDiscogsTitle,
                image: UIImage(systemName: "magnifyingglass")
            ) { _ in
                coordinator.searchDiscogs()
            },
            UIAction(
                title: importMusicTitle,
                image: UIImage(systemName: "square.and.arrow.down")
            ) { _ in
                coordinator.importMusic()
            }
        ])
    }
}

// MARK: - Grid Style Collection (Portrait)

struct GridCollectionView: View {
    @Namespace private var albumHeroNamespace

    @Query private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager

    @State private var showLibrary = false
    @State private var searchText = ""
    @AppStorage("albumSortOrder") private var sortOrder: AlbumSortOrder = .recentlyAdded
    @State private var heroPresentation: AlbumHeroPresentation?
    @State private var flipFrames: [String: CGRect] = [:]
    @State private var detailReturnAlbumID: UUID?
    @State private var showDiscogsSearch = false
    @State private var showMusicImport = false
    @State private var filterGenre: String?
    @State private var filterTag: String?
    @State private var filterDecade: Int?  // e.g. 1970, 1980...
    @State private var isDraggingScrubber = false
    @State private var scrubberViewportSize: CGSize = .zero
    @State private var scrubberViewportOriginY: CGFloat = 0
    @State private var highlightedSection: String?
    @State private var visibleSection: String?
    @State private var albumToDelete: Album?
    @State private var showDeleteConfirm = false
    @State private var albumToColor: Album?
    @State private var showColorPicker = false
    @State private var disintegratingAlbum: Album?
    @State private var scrubberPreviewAlbums: [Album] = []
    @State private var albumToShare: Album?
    @State private var isInitialLoad = true
    @State private var isFanOverlayVisible = false
    @State private var fanInteractionPhase: FanInteractionPhase = .indexing
    @State private var fanProgress: Double = 0
    @State private var fanTextTransitionValue: Double = 0
    @State private var fanSelectedAlbum: Album?
    @Namespace private var gridFanNamespace
    @State private var fanFocusTask: Task<Void, Never>?
    @State private var isDraggingFanQueue = false
    @State private var fanDragStartProgress: Double?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    private var hasActiveFilters: Bool {
        filterGenre != nil || filterTag != nil || filterDecade != nil
    }

    private var allGenres: [String] {
        Array(Set(albums.compactMap(\.genre))).sorted()
    }

    private var allTags: [String] {
        Array(Set(albums.flatMap(\.tags))).sorted()
    }

    private var allDecades: [Int] {
        let years = albums.compactMap(\.releaseYear)
        let decades = Set(years.map { ($0 / 10) * 10 })
        return decades.sorted()
    }

    private var filteredAlbums: [Album] {
        var result = albums

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.tags.contains(where: { $0.lowercased().contains(query) })
            }
        }

        // Genre filter
        if let genre = filterGenre {
            result = result.filter { $0.genre == genre }
        }

        // Tag filter
        if let tag = filterTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        // Decade filter
        if let decade = filterDecade {
            result = result.filter {
                guard let year = $0.releaseYear else { return false }
                return year >= decade && year < decade + 10
            }
        }

        return sortOrder.sorted(result)
    }

    /// All available filter options combined into a flat list for the inline chips.
    private var allFilterOptions: [FilterOption] {
        var options: [FilterOption] = [
            FilterOption(label: L("filter.all"), type: .all)
        ]
        for genre in allGenres {
            options.append(FilterOption(label: genre, type: .genre))
        }
        for decade in allDecades {
            options.append(FilterOption(label: "\(decade)s", type: .decade, value: decade))
        }
        for tag in allTags {
            options.append(FilterOption(label: tag, type: .tag))
        }
        return options
    }

    // MARK: - Section Index

    /// Group filteredAlbums into sections based on current sort order.
    /// Pinned albums get their own section at the top.
    private var sectionedAlbums: [(key: String, albums: [Album])] {
        let sorted = filteredAlbums
        let pinned = sorted.filter { $0.isPinned }
        let unpinned = sorted.filter { !$0.isPinned }

        var sections: [(key: String, albums: [Album])] = []

        // Pinned section at top
        if !pinned.isEmpty {
            sections.append((key: "pinned", albums: pinned))
        }

        // Regular sections from unpinned albums
        var currentKey = ""
        var currentGroup: [Album] = []

        for album in unpinned {
            let key = sectionKey(for: album)
            if key != currentKey {
                if !currentGroup.isEmpty {
                    sections.append((key: currentKey, albums: currentGroup))
                }
                currentKey = key
                currentGroup = [album]
            } else {
                currentGroup.append(album)
            }
        }
        if !currentGroup.isEmpty {
            sections.append((key: currentKey, albums: currentGroup))
        }
        return sections
    }

    private var sectionItems: [SectionItem] {
        sectionedAlbums.map { section in
            SectionItem(key: section.key, shortLabel: sectionShortLabel(section.key))
        }
    }

    private func sectionKey(for album: Album) -> String {
        switch sortOrder {
        case .titleAZ:
            let first = album.title.folding(options: .diacriticInsensitive, locale: .current)
                .prefix(1).uppercased()
            return first.first?.isLetter == true ? first : "#"
        case .artist:
            let first = album.artist.folding(options: .diacriticInsensitive, locale: .current)
                .prefix(1).uppercased()
            return first.first?.isLetter == true ? first : "#"
        case .year:
            guard let year = album.releaseYear else { return "Unknown" }
            let decade = (year / 10) * 10
            return "\(decade)s"
        case .recentlyAdded:
            guard let date = album.addedDate else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: date)
        }
    }

    private func sectionShortLabel(_ key: String) -> String {
        switch sortOrder {
        case .titleAZ, .artist:
            return key // Single letter
        case .year:
            // "1970s" → "'70s"
            if key.count >= 5, let decade = Int(key.dropLast(1)) {
                return "'\(decade % 100)s"
            }
            return key
        case .recentlyAdded:
            // "2024-03" → "Mar"
            let parts = key.split(separator: "-")
            if parts.count == 2, let month = Int(parts[1]) {
                let symbols = Calendar.current.shortMonthSymbols
                if month >= 1 && month <= 12 {
                    return symbols[month - 1]
                }
            }
            return key
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor
                    .ignoresSafeArea()

                if isInitialLoad && !albums.isEmpty {
                    // Keep the navigation title, add button and searchable UI
                    // live while only the collection content is loading.
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 0) {
                                // Filter chips placeholder
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(0..<5, id: \.self) { i in
                                            SkeletonBlock(
                                                width: i == 0 ? 40 : CGFloat([55, 65, 75, 60][i - 1]),
                                                height: 32,
                                                cornerRadius: 16
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .padding(.top, 8)

                                // Sort row placeholder
                                HStack {
                                    SkeletonBlock(width: 70, height: 12, cornerRadius: 4)
                                    Spacer()
                                    SkeletonBlock(width: 14, height: 14, cornerRadius: 3)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                                // Grid
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(0..<8, id: \.self) { _ in
                                        SkeletonGridCell(showsShimmer: false)
                                    }
                                }
                                // One coherent light sweep across the grid is
                                // calmer and more legible than independent
                                // animations on every placeholder shape.
                                .shimmer()
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                isInitialLoad = false
                            }
                        }
                    }
                } else if albums.isEmpty {
                    GeometryReader { geo in
                        let screenH = UIScreen.main.bounds.height
                        let topY = geo.frame(in: .global).minY
                        let stableCenter = screenH * 0.52 - topY

                        emptyCollectionContent
                            .frame(width: geo.size.width)
                            .position(x: geo.size.width / 2, y: stableCenter)
                    }
                } else {
                    ZStack(alignment: .trailing) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 0) {
                                    CollectionGlassSearchField(text: $searchText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)

                                    // Inline filter chips (between search bar and grid)
                                    if !allFilterOptions.isEmpty {
                                        inlineFilterChips
                                            .padding(.top, 8)
                                    }

                                    if filteredAlbums.isEmpty {
                                        VStack(spacing: 8) {
                                            Text(L("collection.no_matching"))
                                                .font(.system(size: 14))
                                                .foregroundColor(styleManager.theme.textSecondary)
                                            Button {
                                                clearFilters()
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(styleManager.theme.accentColor)
                                            }
                                        }
                                        .padding(.top, 64)
                                    } else {
                                        // Sort icon row — right-aligned above grid
                                        HStack {
                                            Text("\(filteredAlbums.count) records")
                                                .font(.system(size: 12))
                                                .foregroundColor(styleManager.theme.textSecondary)

                                            Spacer()

                                            Menu {
                                                ForEach(AlbumSortOrder.allCases) { order in
                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.25)) {
                                                            sortOrder = order
                                                        }
                                                    } label: {
                                                        if sortOrder == order {
                                                            Label(order.displayName, systemImage: "checkmark")
                                                        } else {
                                                            Text(order.displayName)
                                                        }
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "arrow.up.arrow.down")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(styleManager.theme.textSecondary)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)

                                        // Sectioned grid
                                        LazyVGrid(columns: columns, spacing: 16, pinnedViews: [.sectionHeaders]) {
                                            ForEach(sectionedAlbums, id: \.key) { section in
                                                Section {
                                                    ForEach(section.albums) { album in
                                                        VinylCoverCard(
                                                            album: album,
                                                            heroNamespace: albumHeroNamespace,
                                                            heroID: gridHeroID(for: album),
                                                            gridFanNamespace: gridFanNamespace,
                                                            isInFan: isFanOverlayVisible
                                                        )
                                                            .disintegrate(
                                                                isActive: Binding(
                                                                    get: { disintegratingAlbum?.id == album.id },
                                                                    set: { if $0 { disintegratingAlbum = album } }
                                                                ),
                                                                particleLayers: 20,
                                                                duration: 0.8
                                                            ) {
                                                                withAnimation {
                                                                    modelContext.delete(album)
                                                                    try? modelContext.save()
                                                                }
                                                                disintegratingAlbum = nil
                                                            }
                                                            .onTapGesture {
                                                                openGridAlbum(album)
                                                            }
                                                            .background {
                                                                AlbumPreviewContextMenu(album: album, enabled: !isFanOverlayVisible,
                                                                    menu: { gridAlbumMenu(album) }, onOpen: openGridAlbum)
                                                            }

                                                    }
                                                } header: {
                                                    Group {
                                                        if section.key == "pinned" {
                                                            Image(systemName: "pin.fill")
                                                                .font(.system(size: 12, weight: .semibold))
                                                        } else {
                                                            Text(section.key)
                                                                .font(.system(size: 14, weight: .semibold))
                                                        }
                                                    }
                                                    .foregroundColor(styleManager.theme.textSecondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.top, 12)
                                                    .padding(.bottom, 4)
                                                    .background {
                                                        GeometryReader { headerGeo in
                                                            Color.clear.preference(
                                                                key: SectionHeaderPositionsKey.self,
                                                                value: [
                                                                    section.key: headerGeo.frame(
                                                                        in: .named("collectionScroll")
                                                                    ).minY
                                                                ]
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 16) // Room for scrubber
                                        .padding(.top, 4)
                                        .opacity(isFanOverlayVisible ? 0 : 1)
                                    }
                                }
                            }
                            .onChange(of: detailReturnAlbumID) { _, albumID in
                                guard let albumID else { return }
                                // Realize the current album's lazy grid source
                                // behind the cover before interactive dismissal.
                                withTransaction(Transaction(animation: nil)) {
                                    proxy.scrollTo(albumID, anchor: .center)
                                }
                            }
                            .coordinateSpace(name: "collectionScroll")
                            .scrollIndicators(.hidden)
                            .safeAreaPadding(.bottom, 88)
                            .onPreferenceChange(SectionHeaderPositionsKey.self) { positions in
                                updateVisibleSection(from: positions)
                            }
                            .onChange(of: highlightedSection) { _, newSection in
                                guard !isFanOverlayVisible else { return }
                                if let sectionKey = newSection,
                                   let firstAlbum = sectionedAlbums.first(where: { $0.key == sectionKey })?.albums.first {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        proxy.scrollTo(firstAlbum.id, anchor: .top)
                                    }
                                }
                            }
                        }

                    }
                }

                if isFanOverlayVisible, !filteredAlbums.isEmpty {
                    fanCollectionOverlay
                        .transition(.identity)
                        .zIndex(20)
                        // Keep the section scrubber's active drag alive. Once
                        // released, the focused overlay becomes interactive.
                        .allowsHitTesting(!isDraggingScrubber)


                    VStack {
                        HStack {
                            Spacer()
                            Button(action: dismissFanOverlay) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(styleManager.theme.textPrimary)
                            .accessibilityLabel("關閉扇形索引")
                        }
                        Spacer()
                    }
                    .padding(20)
                    .zIndex(40)
                }

                // One persistent index owns the drag across both modes.
                if !filteredAlbums.isEmpty {
                    sectionIndexScrubber
                        .zIndex(30)
                }

            }
            .navigationTitle(L("collection.title"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLibrary) { LibraryView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLibrary = true } label: { Label(L("library.title"), systemImage: "music.note.list") }
                }
                ToolbarItem(placement: .primaryAction) {
                    NativeTintedMenuButton(
                        accentColor: styleManager.theme.accentColor,
                        accessibilityLabel: L("album.add"),
                        searchDiscogsTitle: L("collection.search_discogs"),
                        importMusicTitle: L("collection.import_music"),
                        searchDiscogs: {
                            showDiscogsSearch = true
                        },
                        importMusic: {
                            showMusicImport = true
                        }
                    )
                    .frame(width: 44, height: 44)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showDiscogsSearch) {
                DiscogsSearchView()
                    .environmentObject(collectionVM)
                    .environmentObject(styleManager)
                    .environmentObject(musicServiceManager)
            }
            .sheet(isPresented: $showMusicImport) {
                MusicLibraryImportView()
                    .environmentObject(collectionVM)
                    .environmentObject(styleManager)
                    .environmentObject(musicServiceManager)
            }
            .alert(L("album.delete_title"), isPresented: $showDeleteConfirm) {
                Button(L("album.delete_button"), role: .destructive) {
                    if let album = albumToDelete {
                        // Stop playback if deleting the currently playing album
                        if collectionVM.currentAlbum?.id == album.id {
                            musicServiceManager.pause()
                            collectionVM.stopPlayback()
                            collectionVM.currentAlbum = nil
                            collectionVM.currentTrack = nil
                        }
                        // Trigger disintegration animation — actual delete happens in completion
                        disintegratingAlbum = album
                        albumToDelete = nil
                    }
                }
                Button(L("album.cancel"), role: .cancel) {
                    albumToDelete = nil
                }
            } message: {
                if let album = albumToDelete {
                    Text(L("album.delete_confirm", album.title))
                }
            }
            // ImportProgressBanner is now shown in ContentView above the mini player
            .sheet(isPresented: $showColorPicker) {
                if let album = albumToColor {
                    vinylColorPickerSheet(for: album)
                }
            }
            .sheet(item: $albumToShare) { album in
                ShareSheetView(data: ShareCardData(album: album, baseStyle: styleManager.turntableBaseStyle))
                    .environmentObject(styleManager)
            }
            // Transparent modal keeps the navigation bar and collection layout in place.
            .environment(\.hiddenAlbumFlipSource, heroPresentation?.sourceID)
            .fullScreenCover(item: $heroPresentation) { presentation in
                AlbumFlipPresentation(album: presentation.album, sourceFrame: presentation.frame,
                                      dismiss: { heroPresentation = nil }) {
                AlbumDetailView(album: presentation.album, albums: sectionedAlbums.flatMap(\.albums),
                                onAlbumChange: { album in
                    if presentation.sourceID.hasPrefix("fan-"),
                       let index = filteredAlbums.firstIndex(where: { $0.id == album.id }) {
                        let progress = filteredAlbums.count > 1
                            ? Double(index) / Double(filteredAlbums.count - 1) : 0
                        withTransaction(Transaction(animation: nil)) {
                            fanProgress = progress
                            fanTextTransitionValue = progress
                            fanSelectedAlbum = album
                        }
                    } else {
                        detailReturnAlbumID = album.id
                    }
                })
                    .environmentObject(collectionVM)
                    .environmentObject(styleManager)
                    .environmentObject(musicServiceManager)
                }
            }
            .onPreferenceChange(AlbumFlipFrames.self) { flipFrames = $0 }
        }
    }

    private func gridAlbumMenu(_ album: Album) -> UIMenu {
        UIMenu(children: [
            albumContextAction(L("collection.play"), symbol: "play.fill") { collectionVM.play(album: album) },
            albumContextAction(L("vinyl_color.change"), symbol: "paintpalette") {
                albumToColor = album
                showColorPicker = true
            },
            albumContextAction(album.isPinned ? L("collection.unpin") : L("collection.pin"),
                               symbol: album.isPinned ? "pin.slash" : "pin") {
                album.isPinned.toggle()
                try? modelContext.save()
                HapticManager.shared.impact(styleManager.hapticIntensity)
            },
            albumContextAction(L("share.title"), symbol: "square.and.arrow.up") { albumToShare = album },
            UIMenu(options: .displayInline, children: [
                albumContextAction(L("collection.delete"), symbol: "trash", destructive: true) {
                    albumToDelete = album
                    showDeleteConfirm = true
                    HapticManager.shared.notification(styleManager.hapticIntensity, type: .warning)
                }
            ])
        ])
    }

    // MARK: - Fan Index Overlay

    private var fanCollectionOverlay: some View {
        GeometryReader { geo in
            let fanWidth = max(1, geo.size.width)
            let cardSize = fanWidth * fanOverlayConfig.cardWidthRatio

            ZStack {
                styleManager.theme.backgroundColor
                    // Preserve the navigation bar's large-title region while
                    // still filling beneath the bottom safe area.
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.opacity)

                FanCardStack(
                    items: filteredAlbums,
                    progress: fanProgress,
                    isFocused: fanInteractionPhase == .focused,
                    config: fanOverlayConfig
                ) { album in
                    AlbumCoverView(album: album, size: cardSize)
                        .matchedGeometryEffect(id: album.id, in: gridFanNamespace)
                        .transition(.identity)
                        .albumFlipSource(fanHeroID(for: album))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard fanSelectedAlbum?.id == album.id else { return }
                            openFanAlbum(album)
                        }
                }
                .frame(width: fanWidth, height: geo.size.height)
                .clipped()
                // The queue itself is draggable, not just the edge scrubber.
                .contentShape(Rectangle())
                .gesture(fanQueueDrag)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let album = fanSelectedAlbum {
                    VStack {
                        HStack(alignment: .top) {
                            FanMetadataPanel(
                                title: album.title.uppercased(),
                                subtitle: album.artist,
                                detail: fanDetail(for: album),
                                transitionValue: fanTextTransitionValue,
                                isLeadingAligned: true,
                                showsDetail: fanInteractionPhase == .focused
                            )
                            .padding(.leading, 36)
                            Spacer()
                        }
                        .padding(.top, 24)
                        Spacer()
                    }
                    .animation(.easeInOut(duration: 0.28), value: fanInteractionPhase)
                    .transition(.opacity)
                }

            }
        }
    }

    private var fanOverlayConfig: FanIndexConfig {
        var config = FanIndexConfig()
        config.centersShortQueues = true
        // Preserve the reference composition proportionally on a portrait
        // phone: one-third-width covers, a selected card around the first
        // quarter of the screen, and enough remaining run for the queue to fan
        // visibly toward the upper-right instead of becoming a vertical stack.
        let queueFill = min(1, max(0, CGFloat(filteredAlbums.count - 6) / 12))
        config.aspectRatio = 1
        config.cardWidthRatio = 0.44
        config.cornerRadius = 2
        config.dx = 13
        config.dy = -8
        // Transfer the vertical lift continuously from the outgoing indexed
        // card to the incoming one. Scrubber changes spring between positions;
        // direct queue drags remain fully interactive.
        config.liftRatio = 0.34
        config.liftScale = 1
        config.liftShadowRadius = 5
        config.liftFalloff = 1.0
        config.edgeShadowOpacity = 0
        config.edgeShadowWidth = 0
        config.followAnchorX = 0.04
        config.endShiftRatio = 0.09
        config.endShiftCardRange = 3
        config.queueBaselineY = 0.74 + 0.04 * queueFill
        config.focusScale = 1
        config.focusRecenterEnabled = false
        config.focusDimOpacity = 0.22
        // Entrance geometry now comes from the actual grid cover, not a
        // second synthetic grid inside FanCardStack.
        config.formationProgress = 1
        return config
    }

    // MARK: - Fan Queue Dragging

    /// Drag the cards along the fan's own direction (`dx`, `dy`) to index through
    /// the collection — the same result as scrubbing, driven by the stack itself.
    private var fanQueueDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let count = filteredAlbums.count
                guard count > 1 else { return }

                let start = fanDragStartProgress ?? fanProgress
                if fanDragStartProgress == nil {
                    fanDragStartProgress = start
                    isDraggingFanQueue = true
                    beginFanIndexing()
                }

                // Project the translation onto the fan axis, then convert the
                // result from "cards travelled" into progress.
                let dx = fanOverlayConfig.dx
                let dy = fanOverlayConfig.dy
                let axisLengthSquared = dx * dx + dy * dy
                guard axisLengthSquared > 0 else { return }
                let cardsTravelled = (value.translation.width * dx
                    + value.translation.height * dy) / axisLengthSquared

                setFanProgress(start + Double(cardsTravelled) / Double(count - 1))
            }
            .onEnded { _ in
                fanDragStartProgress = nil
                isDraggingFanQueue = false
                scheduleFanFocus()
            }
    }

    /// Moves the fan and keeps the selected album, the metadata panel and the
    /// scrubber highlight in step with it.
    private func setFanProgress(_ newValue: Double) {
        let clamped = min(1, max(0, newValue))
        let previousIndex = fanIndex(for: fanProgress)
        fanProgress = clamped

        let index = fanIndex(for: clamped)
        guard index != previousIndex, filteredAlbums.indices.contains(index) else { return }

        let album = filteredAlbums[index]
        withAnimation(.snappy(duration: 0.22)) {
            fanTextTransitionValue = clamped
            fanSelectedAlbum = album
        }
        highlightedSection = sectionKey(containing: album)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func fanIndex(for progress: Double) -> Int {
        let count = filteredAlbums.count
        guard count > 1 else { return 0 }
        let raw = Int((progress * Double(count - 1)).rounded())
        return min(count - 1, max(0, raw))
    }

    private func sectionKey(containing album: Album) -> String? {
        sectionedAlbums
            .first { $0.albums.contains { $0.id == album.id } }?
            .key
    }

    private func updateFanOverlay(for sectionKey: String) {
        guard let album = sectionedAlbums.first(where: { $0.key == sectionKey })?.albums.first,
              let index = filteredAlbums.firstIndex(where: { $0.id == album.id }) else { return }

        beginFanIndexing()
        let targetProgress = filteredAlbums.count > 1
            ? Double(index) / Double(filteredAlbums.count - 1)
            : 0
        if isFanOverlayVisible {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                fanSelectedAlbum = album
                fanTextTransitionValue = targetProgress
                fanProgress = targetProgress
            }
        } else {
            fanSelectedAlbum = album
            fanTextTransitionValue = targetProgress
            fanProgress = targetProgress
        }

        if !isFanOverlayVisible {
            collectionVM.isScrubberPreviewActive = true
            withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                isFanOverlayVisible = true
            }
        }
    }

    private func dismissFanOverlay() {
        fanFocusTask?.cancel()
        fanFocusTask = nil
        withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
            fanInteractionPhase = .indexing
            isFanOverlayVisible = false
        }
        collectionVM.isScrubberPreviewActive = false
        // The fan's selected section owns the indicator while the overlay is
        // visible. Hand control back to the grid's visible section only when
        // the overlay is actually dismissed.
        highlightedSection = nil
    }

    private func beginFanIndexing() {
        fanFocusTask?.cancel()
        fanFocusTask = nil
        guard fanInteractionPhase != .indexing else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            fanInteractionPhase = .indexing
        }
    }

    private func scheduleFanFocus() {
        fanFocusTask?.cancel()
        guard isFanOverlayVisible else { return }

        fanInteractionPhase = .settling
        fanFocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled,
                  isFanOverlayVisible,
                  !isDraggingScrubber,
                  !isDraggingFanQueue else { return }

            withAnimation(.easeInOut(duration: 0.28)) {
                fanInteractionPhase = .focused
            }
            fanFocusTask = nil
        }
    }

    // MARK: - Hero Source IDs

    private func gridHeroID(for album: Album) -> String { "grid-\(album.id)" }
    private func fanHeroID(for album: Album) -> String { "fan-\(album.id)" }

    private func openFanAlbum(_ album: Album) {
        openAlbumDetail(album, sourceID: fanHeroID(for: album))
    }

    private func openGridAlbum(_ album: Album) {
        openAlbumDetail(album, sourceID: gridHeroID(for: album))
    }

    /// Capture the tapped cover before mounting the modal animation host.
    private func openAlbumDetail(_ album: Album, sourceID: String) {
        detailReturnAlbumID = nil
        guard let frame = flipFrames[sourceID], frame.width > 0 else { return }
        updateAlbumFlipPresentation {
            heroPresentation = AlbumHeroPresentation(album: album, sourceID: sourceID, frame: frame)
        }
    }

    private func fanDetail(for album: Album) -> String {
        var parts: [String] = []
        if let year = album.releaseYear { parts.append(String(year)) }
        if let genre = album.genre, !genre.isEmpty { parts.append(genre) }
        parts.append(L("collection.tracks_count", album.tracks.count))
        return parts.joined(separator: "\n")
    }

    // MARK: - Vinyl Color Picker Sheet (Context Menu)

    private func vinylColorPickerSheet(for album: Album) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                VinylColorPickerView(
                    customHex: Binding(
                        get: { album.customVinylColorHex },
                        set: { album.customVinylColorHex = $0 }
                    ),
                    vinylOpacity: Binding(
                        get: { album.vinylOpacity },
                        set: { album.vinylOpacity = $0 }
                    ),
                    currentEditionColor: album.selectedEdition?.vinylColor
                )
                .environmentObject(styleManager)
                .padding(16)

                Spacer()
            }
            .background(styleManager.theme.backgroundColor)
            .navigationTitle(L("vinyl_color.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("settings.done")) {
                        showColorPicker = false
                        albumToColor = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(styleManager.theme.accentColor)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Section Index Scrubber

    private var sectionIndexScrubber: some View {
        GeometryReader { geo in
            // Navigation-title/search collapse changes the proposed height as
            // the grid scrolls. Retain the initial viewport for tick metrics;
            // a width change (rotation/window resize) starts a new layout.
            let referenceHeight = scrubberViewportSize.height > 0
                && abs(scrubberViewportSize.width - geo.size.width) < 1
                ? scrubberViewportSize.height : geo.size.height
            let viewportOriginY = geo.frame(in: .global).minY
            let positionCompensation = scrubberViewportSize.height > 0
                && abs(scrubberViewportSize.width - geo.size.width) < 1
                ? scrubberViewportOriginY - viewportOriginY : 0
            // Leave clearance below the filter chips and sort control.
            let indexTopOffset: CGFloat = 48
            let topInset: CGFloat = min(88, referenceHeight * 0.15) + indexTopOffset
            let bottomInset: CGFloat = 112 // Keep the mini player clear.
            let availableHeight = max(12, referenceHeight - topInset - bottomInset)
            let minimumTickSpacing: CGFloat = 11
            let itemCount = filteredAlbums.count
            let capacity = max(1, Int(availableHeight / minimumTickSpacing))
            let tickCount = max(1, min(itemCount, capacity))
            // Give small collections more breathing room without stretching
            // just a few records across the whole screen. Dense collections
            // retain the existing minimum spacing and visible-height cap.
            let maximumTickSpacing: CGFloat = 22
            let tickSpacing = min(maximumTickSpacing, availableHeight / CGFloat(tickCount))
            let railHeight = CGFloat(tickCount) * tickSpacing
            let isExpanded = isFanOverlayVisible || isDraggingScrubber
            let activeProgress = isExpanded ? fanProgress : gridIndexProgress
            let activeTick = activeProgress * Double(max(0, tickCount - 1))

            VStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { tick in
                    let distance = abs(Double(tick) - activeTick)
                    let emphasis = max(0, 1 - distance / 4)
                    let width: CGFloat = isExpanded ? 10 + 30 * CGFloat(emphasis * emphasis) : 10
                    HStack {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(distance < 0.5
                                  ? styleManager.theme.textPrimary
                                  : styleManager.theme.textPrimary.opacity(0.42))
                            .frame(width: width, height: distance < 0.5 && isExpanded ? 3 : 2.5)
//                            .background(.ultraThinMaterial)
                    }
//                    .background(.ultraThinMaterial)
                    .frame(width: 44, height: tickSpacing, alignment: .trailing)
                }
            }
            .frame(width: 44, height: railHeight)
            .background(alignment: .trailing) {
                // Backdrop material blurs the covers beneath the short ticks;
                // the longer active marks can extend naturally over the fan.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 16)
//                    .opacity(0.35)
                    .mask {
                        LinearGradient(colors: [.clear, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    }
//                    .mask {
//                        LinearGradient(stops: [
//                            .init(color: .clear, location: 0),
//                            .init(color: .white, location: 0.06),
//                            .init(color: .white, location: 0.94),
//                            .init(color: .clear, location: 1)
//                        ], startPoint: .top, endPoint: .bottom)
//                    }
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingScrubber {
                            openFanIndex()
                            beginFanIndexing()
                            isDraggingScrubber = true
                        }
                        // Capped marks still map across every album, not just
                        // the first capacity items. End marks select endpoints.
                        let travel = max(1, railHeight - tickSpacing)
                        let progress = itemCount <= 1 ? 0
                            : Double((value.location.y - tickSpacing / 2) / travel)
                        setFanProgress(progress)
                    }
                    .onEnded { _ in
                        isDraggingScrubber = false
                        scheduleFanFocus()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("唱片索引")
            .accessibilityValue("\(fanIndex(for: activeProgress) + 1) / \(itemCount)")
            .accessibilityAdjustableAction { direction in
                openFanIndex()
                let step = 1 / Double(max(1, itemCount - 1))
                switch direction {
                case .increment: setFanProgress(fanProgress + step)
                case .decrement: setFanProgress(fanProgress - step)
                @unknown default: break
                }
                scheduleFanFocus()
            }
            .position(x: geo.size.width - 27,
                      y: positionCompensation + topInset + railHeight / 2)
            .animation(.easeOut(duration: 0.16), value: isExpanded)
            .onAppear {
                if scrubberViewportSize.height <= 0
                    || abs(scrubberViewportSize.width - geo.size.width) >= 1 {
                    scrubberViewportSize = geo.size
                    scrubberViewportOriginY = viewportOriginY
                }
            }
            .onChange(of: geo.size.width) { _, _ in
                scrubberViewportSize = geo.size
                scrubberViewportOriginY = viewportOriginY
            }
        }
    }

    private var gridIndexProgress: Double {
        guard let key = visibleSection,
              let first = sectionedAlbums.first(where: { $0.key == key })?.albums.first,
              let index = filteredAlbums.firstIndex(where: { $0.id == first.id }),
              filteredAlbums.count > 1 else { return 0 }
        return Double(index) / Double(filteredAlbums.count - 1)
    }

    private func openFanIndex() {
        guard !isFanOverlayVisible else { return }
        guard let key = visibleSection ?? sectionItems.first?.key else { return }
        updateFanOverlay(for: key)
        highlightedSection = key
    }

    private func selectFanSection(_ sectionKey: String) {
        guard sectionKey != highlightedSection else { return }
        highlightedSection = sectionKey
        updateFanOverlay(for: sectionKey)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateVisibleSection(from positions: [String: CGFloat]) {
        guard !isDraggingScrubber, !isFanOverlayVisible, !positions.isEmpty else { return }

        let topBoundary: CGFloat = 12
        let nearestPassedSection = positions
            .filter { $0.value <= topBoundary }
            .max(by: { $0.value < $1.value })?.key
        let nearestUpcomingSection = positions
            .min(by: { abs($0.value - topBoundary) < abs($1.value - topBoundary) })?.key
        let currentSection = nearestPassedSection ?? nearestUpcomingSection

        if visibleSection != currentSection {
            visibleSection = currentSection
        }
    }

    // MARK: - Scrubber Preview Overlay

    private var scrubberPreviewOverlay: some View {
        GeometryReader { geo in
            let albums = scrubberPreviewAlbums
            let totalCards = min(albums.count, 10)
            let cardWidth = geo.size.width * 0.82
            let cardHeight = cardWidth * 0.55

            ZStack {
                // Background gradient from album colors
                LinearGradient(
                    colors: scrubberPreviewGradientColors(from: albums),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Cascading 3D cards — bottom card is frontmost, top card is farthest
                ZStack {
                    ForEach(Array(albums.prefix(10).enumerated()), id: \.element.id) { index, album in
                        let reverseIndex = totalCards - 1 - index
                        let scale = 1.0 - CGFloat(index) * 0.02
                        let yOffset = -CGFloat(index) * cardHeight * 0.38

                        ScrubberPreviewCard(
                            album: album,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight
                        )
                        .scaleEffect(x: scale, y: scale, anchor: .bottom)
                        .rotation3DEffect(
                            .degrees(50),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .bottom,
                            perspective: 0.5
                        )
                        .offset(y: yOffset)
                        .zIndex(Double(reverseIndex))
                    }
                }
                .offset(y: geo.size.height * 0.28)
            }
        }
    }

    private func scrubberPreviewGradientColors(from albums: [Album]) -> [Color] {
        let colors = albums.prefix(4).map { $0.color }
        if colors.isEmpty { return [Color.black.opacity(0.85), Color.black.opacity(0.95)] }
        return colors.map { $0.opacity(0.85) } + [Color.black.opacity(0.9)]
    }

    // MARK: - Inline Filter Chips (Apple Mail style)

    private var inlineFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allFilterOptions) { option in
                    let isSelected = isFilterSelected(option)

                    Text(option.label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? Color(.systemBackground) : styleManager.theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? styleManager.theme.accentColor
                                    : styleManager.theme.surfaceColor
                            )
                        )
                        .onTapGesture(count: option.type == .all ? 1 : 2) {
                            // Double-tap on non-All chips → reset to All
                            withAnimation(.easeInOut(duration: 0.2)) {
                                clearFilters()
                            }
                        }
                        .onTapGesture(count: 1) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if option.type == .all {
                                    clearFilters()
                                } else {
                                    toggleFilter(option)
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func isFilterSelected(_ option: FilterOption) -> Bool {
        switch option.type {
        case .all: return !hasActiveFilters
        case .genre: return filterGenre == option.label
        case .decade: return filterDecade == option.value
        case .tag: return filterTag == option.label
        }
    }

    private func toggleFilter(_ option: FilterOption) {
        switch option.type {
        case .all:
            clearFilters()
        case .genre:
            filterGenre = filterGenre == option.label ? nil : option.label
        case .decade:
            filterDecade = filterDecade == option.value ? nil : option.value
        case .tag:
            filterTag = filterTag == option.label ? nil : option.label
        }
    }

    private func clearFilters() {
        filterGenre = nil
        filterTag = nil
        filterDecade = nil
    }

    // MARK: - Empty State

    private var emptyCollectionContent: some View {
        VStack(spacing: 16) {
            VinylRecordIcon(size: 56)

            Text(L("collection.no_records"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            Text(L("collection.no_records_hint"))
                .font(.system(size: 14))
                .foregroundColor(styleManager.theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Vinyl Cover Card

struct AlbumContextPreview: View {
    let album: Album
    var track: Track? = nil

    var body: some View {
        HStack(spacing: 18) {
            AlbumCoverView(album: album, size: 112)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(track?.title ?? album.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                Text(track?.artist ?? album.artist)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.53))
                    .lineLimit(2)
                if track != nil {
                    Text(album.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.53))
                        .lineLimit(2)
                } else if let year = album.releaseYear {
                    Text(String(year))
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.53))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(white: 0.76))
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

struct VinylCoverCard: View {
    let album: Album
    var heroNamespace: Namespace.ID? = nil
    var heroID: String? = nil
    var gridFanNamespace: Namespace.ID? = nil
    var isInFan: Bool = false
    @EnvironmentObject var styleManager: StyleManager
    @State private var dominantColor: Color?

    /// When custom color is set, fill entire disc with that color; otherwise fade to black
    private var discGradientColors: [Color] {
        if album.hasCustomVinylColor {
            let base = Color(hex: album.effectiveVinylColorHex) ?? Color(white: 0.1)
            return [base, base.opacity(0.85)]
        } else {
            return [Color(hex: album.effectiveVinylColorHex) ?? .black, .black]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumSleeveLayout(vinylColors: discGradientColors,
                              vinylOpacity: album.effectiveVinylOpacity,
                              labelColor: dominantColor ?? album.color,
                                      adaptsDefaultVinyl: !album.hasCustomVinylColor &&
                                          (album.selectedEdition?.vinylColor ?? .black) == .black) { sleeveSize in
                Group {
                    if isInFan {
                        Color.clear.frame(width: sleeveSize, height: sleeveSize)
                    } else if let gridFanNamespace, heroNamespace != nil, let heroID {
                        AlbumCoverView(album: album, size: sleeveSize)
                            .matchedGeometryEffect(id: album.id, in: gridFanNamespace)
                            .albumFlipSource(heroID)
                            .transition(.identity)
                    } else if heroNamespace != nil, let heroID {
                        AlbumCoverView(album: album, size: sleeveSize)
                            .albumFlipSource(heroID)
                    } else {
                        AlbumCoverView(album: album, size: sleeveSize)
                    }
                }
            }
            .task(id: album.id) {
                await extractDominantColor()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(styleManager.theme.textPrimary)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundColor(styleManager.theme.textSecondary)
                    .lineLimit(1)

                if let year = album.releaseYear {
                    Text("\(year)")
                        .font(.system(size: 10))
                        .tracking(0.3)
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Dominant Color Extraction

    private func extractDominantColor() async {
        // Try custom cover first
        if let data = album.customCoverImageData {
            if let color = DominantColorExtractor.dominantColor(from: data) {
                await MainActor.run { dominantColor = color }
                return
            }
        }

        // Try remote artwork URL
        if let urlString = album.displayArtworkURL,
           let url = URL(string: urlString) {
            if let color = await DominantColorExtractor.dominantColor(from: url) {
                await MainActor.run { dominantColor = color }
                return
            }
        }

        // Fallback to album's stored color
        await MainActor.run { dominantColor = album.color }
    }
}

// MARK: - Scrubber Preview Card

struct ScrubberPreviewCard: View {
    let album: Album
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Main card face
            ZStack(alignment: .top) {
                // Album artwork
                AlbumCoverView(album: album, size: cardWidth)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()

                // Title label bar
                HStack(spacing: 0) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    + Text("  \(album.artist)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                }
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: cardWidth * 0.88)
                .background(
                    Capsule()
                        .fill(album.color.opacity(0.85))
                )
                .padding(.top, 8)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Card "thickness" edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.gray.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: cardWidth - 2, height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 8)
    }
}

private struct CollectionGlassSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            TextField(L("collection.search_prompt"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}
