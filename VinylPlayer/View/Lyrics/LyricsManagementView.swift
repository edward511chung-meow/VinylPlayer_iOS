import SwiftUI
import SwiftData

// MARK: - Lyrics Management View

/// A full-screen sheet listing all tracks with lyrics.
/// Supports browsing synced/plain lyrics, editing, deleting, and re-fetching from LRCLIB.
struct LyricsManagementView: View {
    @Query(sort: \Album.title) private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var styleManager: StyleManager

    @State private var searchText = ""
    @State private var filterMode: LyricsFilterMode = .all
    @State private var selectedTrack: Track?
    @State private var isFetchingAll = false
    @State private var fetchProgress: (done: Int, total: Int)?

    enum LyricsFilterMode: String, CaseIterable {
        case all, synced, plain, none

        var label: String {
            switch self {
            case .all:    return L("lyrics_mgmt.filter_all")
            case .synced: return L("lyrics_mgmt.filter_synced")
            case .plain:  return L("lyrics_mgmt.filter_plain")
            case .none:   return L("lyrics_mgmt.filter_none")
            }
        }
    }

    /// All tracks flattened from albums, sorted by album then track number.
    private var allTracks: [Track] {
        albums.flatMap { $0.sortedTracks }
    }

    /// Filtered tracks based on search and filter mode.
    private var filteredTracks: [Track] {
        var tracks = allTracks

        // Filter by lyrics type
        switch filterMode {
        case .all:
            break
        case .synced:
            tracks = tracks.filter { hasSyncedLyrics($0) }
        case .plain:
            tracks = tracks.filter {
                guard let lyr = $0.lyrics, !lyr.isEmpty else { return false }
                return !hasSyncedLyrics($0)
            }
        case .none:
            tracks = tracks.filter { $0.lyrics == nil || $0.lyrics!.isEmpty }
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            tracks = tracks.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.albumTitle.lowercased().contains(query)
            }
        }

        return tracks
    }

    private var lyricsStats: (total: Int, synced: Int, plain: Int, none: Int) {
        let all = allTracks
        let synced = all.filter { hasSyncedLyrics($0) }.count
        let withLyrics = all.filter { $0.lyrics != nil && !$0.lyrics!.isEmpty }.count
        let plain = withLyrics - synced
        let none = all.count - withLyrics
        return (all.count, synced, plain, none)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Stats bar
                    statsBar

                    // Filter chips
                    filterChips
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                    // Track list
                    if filteredTracks.isEmpty {
                        emptyState
                    } else {
                        trackList
                    }
                }
            }
            .searchable(text: $searchText, prompt: L("lyrics_mgmt.search_placeholder"))
            .navigationTitle(L("lyrics_mgmt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        fetchAllMissingLyrics()
                    } label: {
                        if isFetchingAll {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 15))
                                .foregroundColor(styleManager.theme.accentColor)
                        }
                    }
                    .disabled(isFetchingAll)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(item: $selectedTrack) { track in
                LyricsDetailView(track: track)
                    .environmentObject(styleManager)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        let stats = lyricsStats
        return HStack(spacing: 16) {
            statBadge(count: stats.total, label: L("lyrics_mgmt.stat_total"), color: .primary)
            statBadge(count: stats.synced, label: L("lyrics_mgmt.stat_synced"), color: .green)
            statBadge(count: stats.plain, label: L("lyrics_mgmt.stat_plain"), color: .orange)
            statBadge(count: stats.none, label: L("lyrics_mgmt.stat_none"), color: .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        // Fetch progress overlay
        .overlay {
            if let progress = fetchProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(L("lyrics_mgmt.fetching_progress", progress.done, progress.total))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .tracking(0.3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LyricsFilterMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        filterMode = mode
                    }
                    HapticManager.shared.selectionTick(styleManager.hapticIntensity)
                } label: {
                    Text(mode.label)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.3)
                        .foregroundColor(filterMode == mode ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(filterMode == mode ? styleManager.theme.accentColor : Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.pressable)
            }
            Spacer()
        }
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            ForEach(filteredTracks) { track in
                trackRow(track)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(styleManager.theme.textSecondary.opacity(0.15))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func trackRow(_ track: Track) -> some View {
        Button {
            selectedTrack = track
        } label: {
            HStack(spacing: 12) {
                // Album art
                if let album = track.album,
                   let data = album.customCoverImageData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Lyrics status badge
                lyricsStatusBadge(for: track)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                track.lyrics = nil
                try? modelContext.save()
                HapticManager.shared.notification(styleManager.hapticIntensity, type: .warning)
            } label: {
                Label(L("lyrics_mgmt.delete"), systemImage: "trash")
            }

            Button {
                Task { await refetchLyrics(for: track) }
            } label: {
                Label(L("lyrics_mgmt.refetch"), systemImage: "arrow.clockwise")
            }
            .tint(styleManager.theme.accentColor)
        }
    }

    private func lyricsStatusBadge(for track: Track) -> some View {
        Group {
            if hasSyncedLyrics(track) {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(L("lyrics_mgmt.synced"))
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.3)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12), in: Capsule())
            } else if let lyr = track.lyrics, !lyr.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                    Text(L("lyrics_mgmt.plain"))
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.3)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12), in: Capsule())
            } else {
                Text(L("lyrics_mgmt.no_lyrics"))
                    .font(.system(size: 10))
                    .tracking(0.3)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text(L("lyrics_mgmt.empty"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func fetchAllMissingLyrics() {
        guard !isFetchingAll else { return }
        isFetchingAll = true

        let tracksWithoutLyrics = allTracks.filter { $0.lyrics == nil || $0.lyrics!.isEmpty }
        let total = tracksWithoutLyrics.count

        Task {
            var done = 0
            for track in tracksWithoutLyrics {
                await MainActor.run {
                    fetchProgress = (done, total)
                }

                let result = await LyricsService.shared.fetchSyncedLyrics(
                    title: track.title,
                    artist: track.artist,
                    albumTitle: track.albumTitle,
                    duration: track.duration > 0 ? track.duration : nil
                )

                await MainActor.run {
                    if let synced = result?.syncedLyrics, !synced.isEmpty {
                        track.lyrics = synced
                    } else if let plain = result?.plainLyrics, !plain.isEmpty {
                        track.lyrics = plain
                    }
                    done += 1
                    fetchProgress = (done, total)
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            await MainActor.run {
                try? modelContext.save()
                isFetchingAll = false
                fetchProgress = nil
                HapticManager.shared.notification(styleManager.hapticIntensity, type: .success)
            }
        }
    }

    private func refetchLyrics(for track: Track) async {
        let result = await LyricsService.shared.fetchSyncedLyrics(
            title: track.title,
            artist: track.artist,
            albumTitle: track.albumTitle,
            duration: track.duration > 0 ? track.duration : nil
        )

        await MainActor.run {
            if let synced = result?.syncedLyrics, !synced.isEmpty {
                track.lyrics = synced
            } else if let plain = result?.plainLyrics, !plain.isEmpty {
                track.lyrics = plain
            }
            try? modelContext.save()
            HapticManager.shared.notification(styleManager.hapticIntensity, type: .success)
        }
    }

    // MARK: - Helpers

    private func hasSyncedLyrics(_ track: Track) -> Bool {
        guard let lyr = track.lyrics, !lyr.isEmpty else { return false }
        let lines = LyricLine.fromLRC(lyr)
        return lines.count > 1 && lines.contains(where: { $0.startTime > 0 })
    }
}

// MARK: - Lyrics Detail View

/// Shows the full lyrics for a single track, with timestamps for synced lyrics.
/// Supports editing and re-fetching.
struct LyricsDetailView: View {
    @Bindable var track: Track
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var styleManager: StyleManager

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isFetching = false
    @State private var showRefetchConfirm = false

    private var lyricLines: [LyricLine] {
        guard let lyr = track.lyrics, !lyr.isEmpty else { return [] }
        return LyricLine.fromLRC(lyr)
    }

    private var isSynced: Bool {
        lyricLines.count > 1 && lyricLines.contains(where: { $0.startTime > 0 })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor.ignoresSafeArea()

                if isEditing {
                    editingView
                } else {
                    lyricsContentView
                }
            }
            .navigationTitle(track.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        // Edit / Save toggle
                        Button {
                            if isEditing {
                                // Save
                                track.lyrics = editText.isEmpty ? nil : editText
                                try? modelContext.save()
                                HapticManager.shared.notification(styleManager.hapticIntensity, type: .success)
                            } else {
                                editText = track.lyrics ?? ""
                            }
                            withAnimation(.spring(duration: 0.2)) {
                                isEditing.toggle()
                            }
                            HapticManager.shared.impact(styleManager.hapticIntensity)
                        } label: {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isEditing ? .white : styleManager.theme.accentColor)
                        }
                        .if(isEditing) { view in
                            view
                                .buttonStyle(.borderedProminent)
                                .tint(styleManager.theme.accentColor)
                        }

                        // Refetch
                        Button {
                            if track.lyrics != nil && !track.lyrics!.isEmpty {
                                showRefetchConfirm = true
                            } else {
                                refetch()
                            }
                        } label: {
                            if isFetching {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(styleManager.theme.accentColor)
                            }
                        }
                        .disabled(isFetching)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .alert(L("lyrics_mgmt.refetch_confirm_title"), isPresented: $showRefetchConfirm) {
                Button(L("album.cancel"), role: .cancel) {}
                Button(L("lyrics_mgmt.refetch"), role: .destructive) {
                    refetch()
                }
            } message: {
                Text(L("lyrics_mgmt.refetch_confirm_message"))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Lyrics Content (Read Mode)

    private var lyricsContentView: some View {
        Group {
            if let lyr = track.lyrics, !lyr.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        // Track metadata header
                        trackHeader

                        if isSynced {
                            syncedLyricsView
                        } else {
                            plainLyricsView(lyr)
                        }
                    }
                    .padding(.bottom, 32)
                }
            } else {
                noLyricsView
            }
        }
    }

    private var trackHeader: some View {
        VStack(spacing: 4) {
            Text(track.artist)
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            if isSynced {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text(L("lyrics_mgmt.synced_label", lyricLines.count))
                        .font(.system(size: 11))
                        .tracking(0.3)
                }
                .foregroundColor(.green)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Synced Lyrics (with timestamps)

    private var syncedLyricsView: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 12) {
                    // Timestamp
                    Text(formatTimestamp(line.startTime))
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(styleManager.theme.accentColor.opacity(0.7))
                        .frame(width: 52, alignment: .trailing)

                    // Lyric text
                    Text(line.text)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if index < lyricLines.count - 1 {
                    Divider()
                        .padding(.leading, 80)
                        .opacity(0.3)
                }
            }
        }
    }

    // MARK: - Plain Lyrics

    private func plainLyricsView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }

    // MARK: - No Lyrics

    private var noLyricsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.quote")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.3))
            Text(L("lyrics_mgmt.no_lyrics_detail"))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                refetch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(L("lyrics_mgmt.fetch_now"))
                }
                .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(styleManager.theme.accentColor)
            .disabled(isFetching)
            Spacer()
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        TextEditor(text: $editText)
            .font(.system(size: 14, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    // MARK: - Actions

    private func refetch() {
        isFetching = true
        Task {
            let result = await LyricsService.shared.fetchSyncedLyrics(
                title: track.title,
                artist: track.artist,
                albumTitle: track.albumTitle,
                duration: track.duration > 0 ? track.duration : nil
            )

            await MainActor.run {
                if let synced = result?.syncedLyrics, !synced.isEmpty {
                    track.lyrics = synced
                } else if let plain = result?.plainLyrics, !plain.isEmpty {
                    track.lyrics = plain
                }
                try? modelContext.save()
                isFetching = false
                if isEditing {
                    editText = track.lyrics ?? ""
                }
                HapticManager.shared.notification(styleManager.hapticIntensity, type: .success)
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let min = Int(time) / 60
        let sec = Int(time) % 60
        let ms = Int((time - Double(Int(time))) * 100)
        return String(format: "%d:%02d.%02d", min, sec, ms)
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
