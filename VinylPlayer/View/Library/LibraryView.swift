import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @Query(sort: \LibraryPlaylist.createdAt, order: .reverse) private var playlists: [LibraryPlaylist]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { LibrarySongsView(title: L("library.songs"), tracks: tracks) } label: {
                        Label(L("library.songs"), systemImage: "music.note.list")
                    }
                    NavigationLink { artists } label: {
                        Label(L("library.artists"), systemImage: "music.mic")
                    }
                    NavigationLink { LibrarySongsView(title: L("library.favorites"), tracks: tracks.filter(\.isFavorite)) } label: {
                        Label(L("library.favorites"), systemImage: "star.fill")
                    }
                }
                Section {
                    Button { name = ""; creating = true } label: {
                        Label(L("library.new_playlist"), systemImage: "plus")
                    }
                    ForEach(playlists) { playlist in
                        NavigationLink { LibraryPlaylistView(playlist: playlist) } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                    .onDelete { indices in
                        for index in indices { context.delete(playlists[index]) }
                        saveLibrary(context)
                    }
                } header: { Text(L("library.playlists")) }
            }
            .navigationTitle(L("library.title"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } } }
            .alert(L("library.new_playlist"), isPresented: $creating) {
                TextField(L("library.name"), text: $name)
                Button(L("common.cancel"), role: .cancel) {}
                Button(L("library.create")) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    context.insert(LibraryPlaylist(name: trimmed)); saveLibrary(context)
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var artists: some View {
        List {
            ForEach(Array(Set(tracks.map(\.artist))).sorted(), id: \.self) { artist in
                NavigationLink {
                    LibrarySongsView(title: artist, tracks: tracks.filter { $0.artist == artist })
                } label: { Label(artist, systemImage: "music.mic") }
            }
        }.navigationTitle(L("library.artists"))
    }
}

struct LibrarySongsView: View {
    let title: String
    let tracks: [Track]
    @EnvironmentObject private var player: CollectionViewModel
    @State private var search = ""
    private var filtered: [Track] {
        tracks.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.albumTitle)".localizedStandardContains(search) }
    }
    var body: some View {
        List {
            if !filtered.isEmpty {
                Section {
                    Button { player.playTracks(filtered) } label: { Label(L("library.play"), systemImage: "play.fill") }
                    Button { player.playTracks(filtered.shuffled(), shuffled: true) } label: { Label(L("library.shuffle"), systemImage: "shuffle") }
                }
            }
            ForEach(filtered) { track in
                LibraryTrackRow(track: track) { player.playTracks(filtered, startingAt: track.id) }
            }
        }
        .safeAreaPadding(.bottom, 128)
        .overlay { if filtered.isEmpty { ContentUnavailableView.search(text: search) } }
        .searchable(text: $search, prompt: L("library.search"))
        .navigationTitle(title)
    }
}

struct LibraryTrackRow: View {
    @Bindable var track: Track
    let play: () -> Void
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var player: CollectionViewModel
    @State private var adding = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    if let album = track.album { AlbumCoverView(album: album, size: 48) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).foregroundStyle(.primary).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if player.currentTrack?.id == track.id { Image(systemName: player.isPlaying ? "waveform" : "pause.fill") }
                    if track.isFavorite { Image(systemName: "star.fill").font(.caption) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu { actions } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }.accessibilityLabel(L("library.actions") + ": " + track.title)
        }
        .contextMenu { actions }
        .sheet(isPresented: $adding) { AddTrackToPlaylistView(track: track) }
    }

    @ViewBuilder private var actions: some View {
        Button {
            track.isFavorite.toggle(); saveLibrary(context)
        } label: { Label(L(track.isFavorite ? "library.unfavorite" : "library.favorite"), systemImage: track.isFavorite ? "star.slash" : "star") }
        Button { adding = true } label: { Label(L("library.add_to_playlist"), systemImage: "text.badge.plus") }
        if let album = track.album {
            Button { player.addToQueue(track: track, album: album, playNext: true) } label: { Label(L("queue.play_next"), systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { player.addToQueue(track: track, album: album) } label: { Label(L("queue.play_last"), systemImage: "text.line.last.and.arrowtriangle.forward") }
        }
    }
}

struct AddTrackToPlaylistView: View {
    let track: Track
    @Query(sort: \LibraryPlaylist.name) private var playlists: [LibraryPlaylist]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L("library.name"), text: $name)
                    Button(L("library.create_and_add")) {
                        let playlist = LibraryPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        playlist.add([track]); context.insert(playlist); saveLibrary(context); dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(playlists) { playlist in
                    Button { playlist.add([track]); saveLibrary(context); dismiss() } label: {
                        HStack { Text(playlist.name); Spacer(); if playlist.trackIDs.contains(track.id) { Image(systemName: "checkmark") } }
                    }
                }
            }
            .navigationTitle(L("library.add_to_playlist"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } } }
        }
    }
}

private struct LibraryPlaylistView: View {
    @Bindable var playlist: LibraryPlaylist
    @Query(sort: \Track.title) private var library: [Track]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var player: CollectionViewModel
    @State private var adding = false
    @State private var renaming = false
    @State private var name = ""
    private var tracks: [Track] { playlist.tracks(in: library) }
    var body: some View {
        List {
            Section {
                Button { player.playTracks(tracks) } label: { Label(L("library.play"), systemImage: "play.fill") }.disabled(tracks.isEmpty)
                Button { player.playTracks(tracks.shuffled(), shuffled: true) } label: { Label(L("library.shuffle"), systemImage: "shuffle") }.disabled(tracks.isEmpty)
                Button { adding = true } label: { Label(L("library.add_songs"), systemImage: "plus") }
            }
            Section {
                ForEach(tracks) { track in
                    LibraryTrackRow(track: track) { player.playTracks(tracks, startingAt: track.id) }
                }
                .onDelete { indices in
                    let ids = Set(indices.map { tracks[$0].id })
                    playlist.trackIDs.removeAll { ids.contains($0) }; saveLibrary(context)
                }
                .onMove { source, destination in
                    var ordered = tracks.map(\.id)
                    ordered.move(fromOffsets: source, toOffset: destination)
                    playlist.trackIDs = ordered; saveLibrary(context)
                }
            }
        }
        .safeAreaPadding(.bottom, 128)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
            ToolbarItem(placement: .secondaryAction) { Button(L("library.rename")) { name = playlist.name; renaming = true } }
        }
        .alert(L("library.rename"), isPresented: $renaming) {
            TextField(L("library.name"), text: $name)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.save")) { playlist.name = name.trimmingCharacters(in: .whitespacesAndNewlines); saveLibrary(context) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $adding) { PlaylistSongPicker(playlist: playlist, tracks: library) }
    }
}

private struct PlaylistSongPicker: View {
    let playlist: LibraryPlaylist
    let tracks: [Track]
    @State private var selected = Set<UUID>()
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var body: some View {
        NavigationStack {
            List(tracks.filter { search.isEmpty || "\($0.title) \($0.artist)".localizedStandardContains(search) }) { track in
                Button {
                    if !selected.insert(track.id).inserted { selected.remove(track.id) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: selected.contains(track.id) || playlist.trackIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                    }
                }.disabled(playlist.trackIDs.contains(track.id))
            }
            .searchable(text: $search, prompt: L("library.search"))
            .navigationTitle(L("library.add_songs"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) {
                    playlist.add(tracks.filter { selected.contains($0.id) }); saveLibrary(context); dismiss()
                } }
            }
        }
    }
}

private func saveLibrary(_ context: ModelContext) {
    do { try context.save() }
    catch { ToastManager.shared.error(error.localizedDescription) }
}
