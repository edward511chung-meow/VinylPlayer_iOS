import SwiftUI
import SwiftData

/// Search Discogs for vinyl releases and import them into the collection.
struct DiscogsSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var collectionVM: CollectionViewModel
    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var musicServiceManager: MusicServiceManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var discogsService = DiscogsService.shared
    @State private var searchText = ""
    @State private var searchResults: [DiscogsSearchResult] = []
    @State private var selectedRelease: DiscogsRelease?
    @State private var isLoadingRelease = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    resultsList
                }
            }
            .navigationTitle(L("discogs.title"))
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
            .sheet(item: releaseBinding) { release in
                DiscogsReleaseDetailView(
                    release: release,
                    onImport: { album in
                        let existing = Album.findDuplicate(
                            title: album.title,
                            artist: album.artist,
                            in: modelContext
                        )

                        let targetAlbum: Album
                        let isUpdate: Bool
                        if let existing {
                            existing.mergeFrom(album)
                            targetAlbum = existing
                            isUpdate = true
                        } else {
                            modelContext.insert(album)
                            targetAlbum = album
                            isUpdate = false
                        }

                        try? modelContext.save()

                        // Check milestone notification
                        if !isUpdate {
                            let count = (try? modelContext.fetchCount(FetchDescriptor<Album>())) ?? 0
                            NotificationManager.shared.checkMilestone(albumCount: count)
                        }

                        // Start background tasks via shared manager
                        let appleMusicService = musicServiceManager.services[.appleMusic] as? AppleMusicService
                        ImportTaskManager.shared.startPostImportTasks(
                            album: targetAlbum,
                            isUpdate: isUpdate,
                            appleMusicService: appleMusicService,
                            modelContext: modelContext
                        )

                        // Dismiss immediately — user can interact while tasks run
                        dismiss()
                    }
                )
                .environmentObject(styleManager)
            }
        }
    }

    private var releaseBinding: Binding<DiscogsRelease?> {
        Binding(
            get: { selectedRelease },
            set: { selectedRelease = $0 }
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(styleManager.theme.textSecondary)

                TextField(L("discogs.search_placeholder"), text: $searchText)
                    .foregroundColor(styleManager.theme.textPrimary)
                    .submitLabel(.search)
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(styleManager.theme.textSecondary.opacity(0.5))
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(styleManager.theme.surfaceColor)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    private var resultsList: some View {
        Group {
            if discogsService.isSearching {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { _ in
                            SkeletonListRow(
                                artworkSize: 56,
                                artworkRadius: 8,
                                lineCount: 3
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 40))
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                    Text(L("discogs.no_results"))
                        .foregroundColor(styleManager.theme.textSecondary)
                }
                Spacer()
            } else if searchResults.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                    Text(L("discogs.search_hint"))
                        .foregroundColor(styleManager.theme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults) { result in
                            searchResultRow(result)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func searchResultRow(_ result: DiscogsSearchResult) -> some View {
        Button {
            loadRelease(id: String(result.id))
        } label: {
            HStack(spacing: 12) {
                // Thumbnail — try coverImage first, then thumb, skip empty strings
                let thumbURL: URL? = {
                    let candidates = [result.coverImage, result.thumb]
                    for candidate in candidates {
                        if let str = candidate, !str.isEmpty, let url = URL(string: str) {
                            return url
                        }
                    }
                    return nil
                }()

                CachedAsyncImage(url: thumbURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(styleManager.theme.surfaceColor)
                        .overlay(
                            VinylRecordIcon(size: 28)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(styleManager.theme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let year = result.year {
                            Text(year)
                        }
                        if let country = result.country {
                            Text(country)
                        }
                        if let label = result.label?.first {
                            Text(label)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(styleManager.theme.textSecondary)
                    .lineLimit(1)

                    if let formats = result.format {
                        Text(formats.joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isLoadingRelease {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(styleManager.theme.surfaceColor)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorMessage = nil

        Task {
            do {
                // Detect barcode (all digits, 8-13 chars)
                let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                let isBarcode = trimmed.allSatisfy(\.isNumber) && (8...13).contains(trimmed.count)

                if isBarcode {
                    searchResults = try await DiscogsService.shared.searchByBarcode(trimmed)
                } else {
                    searchResults = try await DiscogsService.shared.searchReleases(query: trimmed)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadRelease(id: String) {
        isLoadingRelease = true
        errorMessage = nil

        Task {
            do {
                let release = try await DiscogsService.shared.fetchRelease(id: id)
                selectedRelease = release
                isLoadingRelease = false
            } catch {
                errorMessage = error.localizedDescription
                isLoadingRelease = false
            }
        }
    }
}

// MARK: - Discogs Release Detail

struct DiscogsReleaseDetailView: View {
    let release: DiscogsRelease
    let onImport: (Album) -> Void

    @EnvironmentObject var styleManager: StyleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Cover art
                        if let imageURL = release.images?.first?.uri,
                           let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(styleManager.theme.surfaceColor)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(ProgressView())
                            }
                            .frame(maxWidth: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 10)
                        }

                        // Info
                        VStack(spacing: 8) {
                            Text(release.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(styleManager.theme.textPrimary)
                                .multilineTextAlignment(.center)

                            Text(release.artists?.first?.name ?? "Unknown")
                                .font(.system(size: 16))
                                .foregroundColor(styleManager.theme.textSecondary)

                            HStack(spacing: 8) {
                                if let year = release.year { infoChip("\(year)") }
                                if let country = release.country { infoChip(country) }
                                if let label = release.labels?.first?.name { infoChip(label) }
                            }
                            .padding(.top, 4)
                        }

                        // Format info
                        if let formats = release.formats {
                            let desc = formats.compactMap(\.descriptions).flatMap { $0 }.joined(separator: ", ")
                            if !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundColor(styleManager.theme.textSecondary.opacity(0.7))
                            }
                        }

                        // Tracklist
                        if let tracks = release.tracklist, !tracks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("discogs.tracklist"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(styleManager.theme.textPrimary)

                                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                                    HStack {
                                        Text(track.position ?? "")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(styleManager.theme.textSecondary)
                                            .frame(width: 32, alignment: .leading)

                                        Text(track.title)
                                            .font(.system(size: 13))
                                            .foregroundColor(styleManager.theme.textPrimary)

                                        Spacer()

                                        if let dur = track.duration, !dur.isEmpty {
                                            Text(dur)
                                                .font(.system(size: 11))
                                                .foregroundColor(styleManager.theme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(styleManager.theme.surfaceColor)
                            )
                        }

                    }
                    .padding(24)
                }
            }
            .navigationTitle(L("discogs.release_details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(styleManager.theme.accentColor)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let album = DiscogsService.shared.convertToAlbum(release: release)
                        onImport(album)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(styleManager.theme.accentColor)
                    }
                }
            }
        }
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(styleManager.theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(styleManager.theme.surfaceColor)
            )
    }
}

// MARK: - Identifiable conformance for DiscogsRelease

extension DiscogsRelease: Identifiable {}
