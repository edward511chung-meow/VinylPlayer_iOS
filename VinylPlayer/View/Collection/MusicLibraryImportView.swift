import SwiftUI
import SwiftData

/// Import albums from connected music services (Apple Music / Spotify) into the vinyl collection.
struct MusicLibraryImportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSource: MusicSource = .appleMusic
    @State private var libraryAlbums: [Album] = []
    @State private var selectedAlbums: Set<UUID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showImportResult = false
    @State private var importResultMessage = ""

    private var availableSources: [MusicSource] {
        [.appleMusic, .spotify].filter { musicServiceManager.isAuthorized($0) }
    }

    private var filteredAlbums: [Album] {
        if searchText.isEmpty { return libraryAlbums }
        let q = searchText.lowercased()
        return libraryAlbums.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                if availableSources.isEmpty {
                    noServicesView
                } else {
                    VStack(spacing: 0) {
                        sourcePicker
                        searchBar

                        if isLoading {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(0..<8, id: \.self) { _ in
                                        SkeletonListRow(
                                            artworkSize: 48,
                                            artworkRadius: 8,
                                            lineCount: 2
                                        )
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .scrollIndicators(.hidden)
                        } else if libraryAlbums.isEmpty {
                            Spacer()
                            Text(L("import.no_albums"))
                                .foregroundColor(styleManager.theme.textSecondary)
                            Spacer()
                        } else {
                            albumList
                        }

                        if !selectedAlbums.isEmpty {
                            importBar
                        }
                    }
                }

                if let error = errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
            .navigationTitle(L("import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(styleManager.theme.textSecondary)
                    }
                }
            }
            .onAppear { loadLibrary() }
            .alert(L("import.complete_title"), isPresented: $showImportResult) {
                Button(L("import.ok")) { dismiss() }
            } message: {
                Text(importResultMessage)
            }
        }
    }

    // MARK: - No Services

    private var noServicesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))

            Text(L("import.no_service"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(styleManager.theme.textSecondary)

            Text(L("import.connect_hint"))
                .font(.system(size: 13))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        Picker(L("import.source"), selection: $selectedSource) {
            ForEach(availableSources) { source in
                Text(source.displayName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: selectedSource) { _, _ in
            loadLibrary()
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(styleManager.theme.textSecondary)
            TextField(L("import.filter"), text: $searchText)
                .foregroundColor(styleManager.theme.textPrimary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Album List

    private var albumList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Select all / deselect
                HStack {
                    Button(selectedAlbums.count == filteredAlbums.count ? L("import.deselect_all") : L("import.select_all")) {
                        if selectedAlbums.count == filteredAlbums.count {
                            selectedAlbums.removeAll()
                        } else {
                            selectedAlbums = Set(filteredAlbums.map(\.id))
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(styleManager.theme.accentColor)

                    Spacer()

                    Text("\(filteredAlbums.count) albums")
                        .font(.system(size: 12))
                        .foregroundColor(styleManager.theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                ForEach(filteredAlbums) { album in
                    albumRow(album)
                }
            }
        }
    }

    private func albumRow(_ album: Album) -> some View {
        let isSelected = selectedAlbums.contains(album.id)

        return Button {
            if isSelected {
                selectedAlbums.remove(album.id)
            } else {
                selectedAlbums.insert(album.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Artwork
                CachedAsyncImage(url: album.artworkURL.flatMap { URL(string: $0) }) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(styleManager.theme.surfaceColor)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                        )
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(styleManager.theme.textPrimary)
                        .lineLimit(1)

                    Text(album.artist)
                        .font(.system(size: 12))
                        .foregroundColor(styleManager.theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary.opacity(0.3))
                    .font(.system(size: 20))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import Bar

    private var importBar: some View {
        Button {
            importSelected()
        } label: {
            Text(L("import.button", selectedAlbums.count))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(styleManager.theme.accentColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }

    // MARK: - Actions

    private func loadLibrary() {
        guard availableSources.contains(selectedSource) else {
            if let first = availableSources.first { selectedSource = first }
            return
        }

        isLoading = true
        errorMessage = nil
        libraryAlbums = []
        selectedAlbums = []

        Task {
            do {
                libraryAlbums = try await musicServiceManager.fetchLibraryAlbums(from: selectedSource)
                isLoading = false

                // Prefetch all artwork URLs for smoother scrolling
                let artworkURLs = libraryAlbums.compactMap { $0.artworkURL }
                if !artworkURLs.isEmpty {
                    ImageCacheManager.shared.prefetch(urls: artworkURLs)
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func importSelected() {
        let toImport = libraryAlbums.filter { selectedAlbums.contains($0.id) }
        var newCount = 0
        var updatedCount = 0

        var importedAlbums: [Album] = []

        for album in toImport {
            // Try to find existing by service ID first, then by title+artist
            let existing = Album.findByServiceId(
                appleMusicId: album.appleMusicId,
                spotifyId: album.spotifyId,
                in: modelContext
            ) ?? Album.findDuplicate(
                title: album.title,
                artist: album.artist,
                in: modelContext
            )

            if let existing {
                existing.mergeFrom(album)
                updatedCount += 1
                importedAlbums.append(existing)
            } else {
                modelContext.insert(album)
                newCount += 1
                importedAlbums.append(album)
            }
        }

        try? modelContext.save()

        // Check milestone notification
        if newCount > 0 {
            let totalCount = (try? modelContext.fetchCount(FetchDescriptor<Album>())) ?? 0
            NotificationManager.shared.checkMilestone(albumCount: totalCount)
        }

        // Trigger post-import tasks (artwork download, lyrics fetch, Apple Music matching)
        let appleMusicService = musicServiceManager.services[.appleMusic] as? AppleMusicService
        for album in importedAlbums {
            ImportTaskManager.shared.startPostImportTasks(
                album: album,
                isUpdate: updatedCount > 0,
                appleMusicService: appleMusicService,
                modelContext: modelContext
            )
        }

        if updatedCount > 0 {
            importResultMessage = "Added \(newCount) new, updated \(updatedCount) existing"
            showImportResult = true
        } else {
            dismiss()
        }
    }
}
