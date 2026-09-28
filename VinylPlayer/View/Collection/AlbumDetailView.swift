import SwiftUI
import SwiftData
import PhotosUI
import Combine

struct AlbumDetailView: View {
    @Query private var collectionAlbums: [Album]
    @AppStorage("albumSortOrder") private var sortOrder: AlbumSortOrder = .recentlyAdded
    @EnvironmentObject private var styleManager: StyleManager
    @State private var selectedID: UUID?
    @State private var browsingAlbums: [Album]
    @State private var needsCollectionOrder: Bool
    @State private var editingAlbumID: UUID?
    private let heroNamespace: Namespace.ID?
    private let heroSourcePrefix: String
    private let onAlbumChange: (Album) -> Void

    init(album: Album, albums: [Album] = [], heroNamespace: Namespace.ID? = nil,
         heroSourcePrefix: String = "grid-", onAlbumChange: @escaping (Album) -> Void = { _ in }) {
        self.heroNamespace = heroNamespace
        self.heroSourcePrefix = heroSourcePrefix
        self.onAlbumChange = onAlbumChange
        _selectedID = State(initialValue: album.id)
        _browsingAlbums = State(initialValue: albums.isEmpty ? [album] : albums)
        _needsCollectionOrder = State(initialValue: albums.isEmpty)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(browsingAlbums) { album in
                        AlbumDetailPage(album: album, onEditingChanged: { editing in
                            if editing {
                                editingAlbumID = album.id
                            } else if editingAlbumID == album.id {
                                editingAlbumID = nil
                            }
                        })
                        // Editing locks the outer pager while the page's own
                        // vertical list and its controls remain usable.
                        .environment(\.isScrollEnabled, true)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(album.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedID)
            .scrollDisabled(editingAlbumID != nil)
            // Allow each page's background to reach the top/bottom safe areas.
            .scrollClipDisabled()
        }
        .onChange(of: selectedID) { old, new in
            if old != nil && new != nil && old != new {
                HapticManager.shared.impact(styleManager.hapticIntensity)
                if let album = browsingAlbums.first(where: { $0.id == new }) {
                    onAlbumChange(album)
                }
            }
        }
        .modifier(AlbumDetailZoomModifier(namespace: heroNamespace,
                                         sourceID: heroSourcePrefix + (selectedID?.uuidString ?? "")))
        .onAppear {
            guard needsCollectionOrder else { return }
            needsCollectionOrder = false
            let initial = browsingAlbums[0]
            let sorted = sortOrder.sorted(collectionAlbums)
            browsingAlbums = sorted.filter(\.isPinned) + sorted.filter { !$0.isPinned }
            if !browsingAlbums.contains(where: { $0.id == initial.id }) {
                browsingAlbums.insert(initial, at: 0)
            }
        }
    }

}

private struct AlbumDetailZoomModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private struct AlbumDetailPage: View {
    @State private var playlistTrack: Track?
    @Bindable var album: Album
    let onEditingChanged: (Bool) -> Void
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeAlbumFlip) private var closeAlbumFlip
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var showMetadata = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showSleeveTransition = false
    @State private var showDeleteConfirm = false
    @State private var isEditing = false
    @State private var newTag = ""
    @State private var showAddTag = false
    @State private var albumImage: UIImage?
    @State private var dominantColor: Color?

//    var playerAnimation: Namespace.ID

    /// Disc gradient matching VinylCoverCard in GridCollectionView.
    private var discGradientColors: [Color] {
        if album.hasCustomVinylColor {
            let base = Color(hex: album.effectiveVinylColorHex) ?? Color(white: 0.1)
            return [base, base.opacity(0.85)]
        } else {
            return [Color(hex: album.effectiveVinylColorHex) ?? .black, .black]
        }
    }

    /// Whether the dominant color is light (luminance > 0.5).
    private var isDominantColorLight: Bool {
        guard let dominantColor else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(dominantColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.5
    }

    // Pushed onto the collection's NavigationStack with a zoom transition, so it
    // must NOT wrap itself in another NavigationStack: that nested container was
    // what reserved a hidden navigation bar's worth of blank space at the top.
    var body: some View {
        ZStack {
            // Immediate fallback: album color gradient
            LinearGradient(
                colors: [
                    dominantColor ?? album.color,
                    (dominantColor ?? album.color).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Smooth transition to extracted image gradient
            if albumImage != nil {
                ImageGradient(
                    image: albumImage,
                    count: 4,
                    animation: .spring(duration: 0.6)
                ) { colors in
                    withAnimation(.spring(duration: 0.4)) {
                        dominantColor = colors.first
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            ScrollView {
                VStack(spacing: 24) {
                    // Share the sleeve/half-exposed record proportions with Collection.
                    AlbumSleeveLayout(vinylColors: discGradientColors,
                                      vinylOpacity: album.effectiveVinylOpacity,
                                      labelColor: dominantColor ?? album.color,
                                      adaptsDefaultVinyl: !album.hasCustomVinylColor &&
                                          (album.selectedEdition?.vinylColor ?? .black) == .black) { sleeveSize in
                        AlbumCoverView(album: album, size: sleeveSize)
                    }
                    .environment(\.colorScheme, systemColorScheme)
                    .frame(maxWidth: 560)

                    // Album info (editable)
                    albumInfoSection

                    // Edition selector
                    if album.editions.count > 1 {
                        editionSection
                    }

                    // Track list
                    trackListSection

                    Button(L("metadata.title"), systemImage: "sparkles") { showMetadata = true }
                        .buttonStyle(.bordered)

                    // Tags
                    tagsSection

                    // Customization (edit mode only)
                    if isEditing {
                        // Vinyl color + opacity
                        VinylColorPickerView(
                            customHex: $album.customVinylColorHex,
                            vinylOpacity: $album.vinylOpacity,
                            currentEditionColor: album.selectedEdition?.vinylColor
                        )
                        .environmentObject(styleManager)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        // Custom cover upload
                        customCoverSection
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        // Delete button
                        deleteSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 24)
                // Clears the floating close / edit / play row above.
                .padding(.top, closeAlbumFlip == nil ? 62 : 72)
                .padding(.bottom, 40)
            }


            VStack {
                HStack(spacing: 12) {
                    Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 42, height: 42)
                                .modifier(AlbumDetailGlassButtonModifier())
                    }
                    .accessibilityLabel(Text("Close"))

                    Spacer()

                    Button {
                        withAnimation(.spring(duration: 0.25)) { isEditing.toggle() }
                        HapticManager.shared.impact(styleManager.hapticIntensity)
                    } label: {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 42, height: 42)
                                .modifier(AlbumDetailGlassButtonModifier())
                    }

                    Button {
                        showSleeveTransition = true
                        collectionVM.play(album: album)
                    } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 42, height: 42)
                                .modifier(AlbumDetailGlassButtonModifier())
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.top, closeAlbumFlip == nil ? 8 : 16)

                Spacer()
            }
        }
        .sheet(isPresented: $showMetadata) { AlbumMetadataView(album: album) }
        .sheet(item: $playlistTrack) { AddTrackToPlaylistView(track: $0) }
        .fullScreenCover(isPresented: $showSleeveTransition) {
            VinylSleeveTransition(album: album) {
                showSleeveTransition = false
                close()
            }
            .environmentObject(styleManager)
            .environment(\.colorScheme, systemColorScheme)
        }
        .onAppear { extractAlbumImage() }
        .onChange(of: album.customCoverImageData) { _, _ in extractAlbumImage() }
        .onChange(of: isEditing) { _, editing in onEditingChanged(editing) }
        .onDisappear {
            if isEditing { onEditingChanged(false) }
        }
        .environment(\.colorScheme, isDominantColorLight ? .light : .dark)
        .alert(L("album.delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("album.delete_button"), role: .destructive) {
                // Stop playback if deleting the currently playing album
                if collectionVM.currentAlbum?.id == album.id {
                    musicServiceManager.pause()
                    collectionVM.stopPlayback()
                    collectionVM.currentAlbum = nil
                    collectionVM.currentTrack = nil
                }
                modelContext.delete(album)
                close()
            }
            Button(L("album.cancel"), role: .cancel) {}
        } message: {
            Text(L("album.delete_confirm", album.title))
        }
    }

    private func close() {
        if let closeAlbumFlip { closeAlbumFlip() } else { dismiss() }
    }

    // MARK: - Album Info

    private var albumInfoSection: some View {
        VStack(spacing: 8) {
            if isEditing {
                TextField(L("album.title_placeholder"), text: $album.title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                TextField(L("album.artist_placeholder"), text: $album.artist)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(album.title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(album.artist)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if let year = album.releaseYear {
                    Label("\(year)", systemImage: "calendar")
                }
                if let genre = album.genre {
                    Label(genre, systemImage: "music.note")
                }
                Label(L("album.tracks_label", album.tracks.count), systemImage: "list.bullet")
            }
            .font(.system(size: 12))
            .tracking(0.3)
            .foregroundColor(.secondary)

        }
    }

    // MARK: - Edition Picker

    private var editionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("album.vinyl_editions"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            ForEach(album.editions) { edition in
                HStack {
                    Circle()
                        .fill(Color(hex: edition.vinylColor.colorHex) ?? .black)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(edition.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(styleManager.theme.textPrimary)

                        if let notes = edition.notes {
                            Text(notes)
                                .font(.system(size: 10))
                                .tracking(0.3)
                                .foregroundColor(styleManager.theme.textSecondary)
                        }
                    }

                    Spacer()

                    if album.selectedEditionId == edition.id || (album.selectedEditionId == nil && edition.id == album.editions.first?.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(styleManager.theme.accentColor)
                            .font(.system(size: 16))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(styleManager.theme.surfaceColor)
                )
                .onTapGesture {
                    album.selectedEditionId = edition.id
                }
            }
        }
    }

    // MARK: - Track List

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("album.tracks"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            ForEach(album.sortedTracks) { track in
                let isNowPlaying = collectionVM.currentAlbum?.id == album.id
                    && collectionVM.currentTrack?.id == track.id

                HStack {
                    if isNowPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .symbolEffect(.variableColor.iterative, isActive: collectionVM.isPlaying)
                            .frame(width: 28, alignment: .leading)
                    } else {
                        Text("\(track.side.rawValue)\(track.trackNumber)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .leading)
                    }

                    Text(track.title)
                        .font(.system(size: 13, weight: isNowPlaying ? .semibold : .regular))
                        .foregroundColor(isNowPlaying ? .black : .primary)
                        .lineLimit(1)
                        .handwrittenHighlight(isActive: isNowPlaying)

                    Spacer()

                    Text(track.duration.formattedDuration)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    collectionVM.play(album: album, track: track)
                }
                .contextMenu {
                    Button(L("library.add_to_playlist"), systemImage: "text.badge.plus") { playlistTrack = track }
                    Button(L(track.isFavorite ? "library.unfavorite" : "library.favorite"), systemImage: "star") {
                        track.isFavorite.toggle()
                        try? modelContext.save()
                    }
                    Button(L("queue.play_next"), systemImage: "text.line.first.and.arrowtriangle.forward") { collectionVM.addToQueue(track: track, album: album, playNext: true) }
                    Button(L("queue.play_last"), systemImage: "text.line.last.and.arrowtriangle.forward") { collectionVM.addToQueue(track: track, album: album) }
                }
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("album.tags"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    showAddTag = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.primary.opacity(0.7))
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(album.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))

                        if isEditing {
                            Button {
                                album.tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(0.15))
                    )
                }

                if album.tags.isEmpty {
                    Text(L("album.no_tags"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert(L("album.add_tag_title"), isPresented: $showAddTag) {
            TextField(L("album.tag_placeholder"), text: $newTag)
            Button(L("album.add")) {
                let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !album.tags.contains(trimmed) {
                    album.tags.append(trimmed)
                }
                newTag = ""
            }
            Button(L("album.cancel"), role: .cancel) { newTag = "" }
        } message: {
            Text(L("album.add_tag_message"))
        }
    }

    // MARK: - Custom Cover Upload

    private var customCoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("album.custom_cover"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                        .foregroundColor(styleManager.theme.textSecondary)
                    Text(L("album.upload_cover"))
                        .font(.system(size: 13))
                        .foregroundColor(styleManager.theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.4))
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        album.customCoverImageData = data
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(styleManager.theme.surfaceColor)
        )
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                Text(L("album.remove_collection"))
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.4)
            }
            .foregroundColor(.red)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(styleManager.theme.surfaceColor)
        )
        .padding(.bottom, 32)
    }

    // MARK: - Image Extraction

    private func extractAlbumImage() {
        // Set album color immediately as fallback
        if dominantColor == nil {
            dominantColor = album.color
        }

        // Local image data — instant
        if let data = album.customCoverImageData,
           let image = UIImage(data: data) {
            withAnimation(.spring(duration: 0.3)) {
                albumImage = image
            }
            return
        }

        // Remote URL via cache
        if let urlString = album.displayArtworkURL {
            Task {
                if let image = await ImageCacheManager.shared.image(for: urlString) {
                    await MainActor.run {
                        withAnimation(.spring(duration: 0.3)) {
                            albumImage = image
                        }
                    }
                }
            }
            return
        }
    }
}

private struct AlbumDetailGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
