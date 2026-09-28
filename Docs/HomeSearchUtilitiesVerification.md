# Home, Search and everyday utilities

## Entry points

- Home: Top Picks uses listening recency and favorites; Recently Played is chronological; Made for You mixes up to 20 tracks with at most three per artist; Rediscover selects previously played albums not heard for at least 14 days. No fake new-release or trending labels.
- Discover: authenticated Apple Music or Spotify catalogue search based on the listener's leading artist. Owned and dismissed albums are excluded. This is an initial heuristic, not collaborative filtering. “Not interested” persists locally and can be reset.
- Search tab: Collection / Apple Music / Spotify. Songs, albums and artists; catalogue results can be imported and played or queued. Provider authorization and access remain required.
- Settings → Backup & Restore: exports albums, artwork, lyrics, favorites, editions, playlists and listening history as JSON. Does not export audio, credentials or settings. Import validates first, previews counts, then merges without clearing the collection. Existing metadata takes precedence; references are remapped and duplicate history IDs skipped.
- Settings → Sleep Timer: 15/30/45/60 minutes, cancellation and native Apple Music end-of-track stop. Countdown is best effort while the application can execute; suspension can delay stopping until resume. No background keepalive workaround.
- Playback status: loading/cancel and failure/retry banner in the main app root.

## Verified

- Debug iOS Simulator build succeeded (`/tmp/vinyl-home-search-backup-final2.log`).
- `Tests/DiscoveryBackup/Check.swift`: 24 passing checks using real SwiftData models in an in-memory simulator harness. Covers recommendation ordering/diversity/stability, JSON round trip, artwork/lyrics/favorites/editions, playlist order, idempotent merge, invalid/versioned backup rejection, reference remapping and timer deadline boundaries.
- Inspected Simulator screenshots for Home, populated local Search, Backup & Restore, and Sleep Timer. Search empty local categories were subsequently hidden; that change compiled successfully.
- Existing app visual styling retained; new explicit spacing uses 8/4 pt multiples.

## Reproducible visual previews

`HomeDesignPreview.swift` contains Home, Library, Search Results, Backup and Sleep Timer previews with a static in-memory fixture. Debug launch arguments:

- `--home-design-preview`
- `--search-design-preview`
- `--backup-design-preview`
- `--sleep-design-preview`

These fixtures do not modify the real collection.

## Still requires device/account verification

1. Authorize each music provider; search a song, import and play it, then queue an album. Check actual subscription/market availability and Spotify transport behavior.
2. Disable connectivity while starting playback; confirm loading ends and Retry recovers after reconnecting. The root playback banner is not presented above every modal sheet.
3. Export through Files, re-import the saved file and confirm preview/merge in a persistent device library. The codec/merge is tested; native Files picker interaction is not automated.
4. Exercise countdown and end-of-track stop while foregrounded, locked, and resumed. Do not infer exact background timer delivery from the value-type boundary tests.
5. Review Home with genuine artwork/history and Dynamic Type. Current screenshots use fixture artwork and the standard Simulator text size.
