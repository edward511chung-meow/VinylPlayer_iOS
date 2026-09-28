# Music library and playback verification

## Implemented

- Collection toolbar → Music Library → Songs / Artists / Favorites / Playlists.
- Song search, favorite toggle, Play Next / Play Last, add to existing or new playlist.
- Playlist creation, rename, multi-song selection, reorder, remove songs, delete playlist.
- Playlist references are ordered track UUIDs; deleting a playlist never deletes album tracks. Deleted album tracks are omitted when resolving a playlist.
- Cross-album song selection uses the existing queue, history and repeat behavior.
- Playback observations reconcile the model independently of Full Player visibility.
- Cancelled selections stop their backend before the next selection begins. Queue preparation cannot undo a subsequent pause command.
- Late lock-screen artwork requests cannot overwrite a newer song. Remote commands register once.
- Queue restore retains progress and repeat/shuffle state without autoplay.
- Cover Flow browsing no longer changes the playing album.

## Automated verification

`Tests/PlaybackQueue/Check.swift` exercises the actual Album, Track, LibraryPlaylist and CollectionViewModel types; notification/Live Activity/system Now Playing outputs are stubbed. 26 assertions cover queue identity/order, repeat, cross-album navigation, restoration, external state reconciliation, favorites and playlist persistence, and non-destructive playlist deletion.

These tests do not validate audio backend/network behavior, interruption handling, or background execution on a device.

## Visual entry

Xcode preview: `HomeDesignPreview(showsLibrary: true)` in HomeDesignPreview.swift.
Debug launch argument: `--library-design-preview`.
Uses an in-memory library, isolated from real collection data.

## Device verification still required

Use a signed build and authorized music service account:

1. Start a song, collapse Full Player, pause from lock screen and Widget; verify audio, mini player and needle all pause.
2. Play a multi-album queue, reorder/remove upcoming songs, lock the phone and check the next song follows that order.
3. Select several songs quickly, then pause during loading; verify no stale song starts later.
4. Disconnect headphones and trigger an audio interruption; confirm the service state reaches the app and widgets.
5. Relaunch while paused: queue and position restore without playing; resume starts the selected track.
6. From Collection → Music Library, create a playlist, add tracks, reorder, play, favorite a track, relaunch and check persistence.
7. Test unavailable songs and authorization failures: playback must settle to paused with an error, not a spinning playing state.

Apple Music system playback currently requires songs resolvable in the device's media library. A mixed-provider queue cannot be handed wholesale to the system Music queue; native queue synchronization reports an error for unresolved entries. Cross-provider continuous background playback remains dependent on each provider's capabilities.
