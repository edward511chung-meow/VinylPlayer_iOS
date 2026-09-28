# Album information enrichment (first version)

## Use

Open an album and choose **Find Missing Information / 補齊專輯資料** below the tracks.

- **Read an Album Folder**: select a single folder through Files. Reads embedded metadata/artwork/lyrics, cover/folder JPG or PNG, and UTF-8 LRC sidecars. Only matches existing songs. Does not import audio, recursively scan folders, implement NAS transport, or write source files.
- **Find Missing Artwork & Lyrics**: search MusicBrainz releases, obtain artwork through Cover Art Archive, and reuse the existing lyrics resolver. Missing artwork does not block lyric lookup. Existing lyrics/covers remain intact.
- **Search / Change Match**: edit search terms without renaming the album; inspect release date, country, notes, track count and artwork, then select a version. Existing artwork replacement requires the explicit toggle.
- **Automatic covers**: opt-in setting applies to future post-import jobs. Requires exactly one matching title/artist/count/year candidate, followed by verification of the ordered track names and known durations (within two seconds). Ambiguous versions are not automatically applied.
- **Undo**: restores supplemented fields only if they still contain the values applied by enrichment. Subsequent manual edits are preserved. Receipt is persisted on Album and included in new backup exports.

## Validation

- Debug iOS Simulator build passed.
- Live MusicBrainz public example search (Abbey Road / The Beatles) returned three candidates using the system TLS trust store and a non-personal User-Agent. This validates connectivity/response shape, not the entire artwork-selection flow.
- `Tests/AlbumEnrichment/Check.swift`: 13 checks passed on iPhone Simulator. Covers unique/ambiguous/version/count matching; preservation of existing data; undo and intervening manual edits; local cover/LRC matching; ambiguous same-title sidecars; no source-file modification.
- Inspected actual Simulator screenshot of the new form via `--metadata-design-preview`. Also available as the **Album Metadata** Xcode preview. It uses an isolated in-memory album.
- Explicit new layout spacing uses 8/4 pt increments.

## Test harness sources

Compile the check as an arm64 iOS Simulator executable with:
`Album.swift`, `Track.swift`, `VinylEdition.swift`, `Color+Hex.swift`, `AlbumEnrichment.swift`, `LocalAlbumMetadata.swift`.
Package/sign it as an ad-hoc Simulator app and run its executable. No account or live service is needed for these checks.

## Remaining manual checks / limits

- Candidate selection and remote artwork retrieval need real album trials; catalogue coverage and availability vary.
- Embedded audio tags depend on AVFoundation's support for the selected format. Automated fixtures exercise standalone cover and LRC, not every audio tagging format.
- Folder access is through Files; direct WebDAV/SMB/OpenSubsonic connectivity and audio streaming remain separate work.
- Existing lyric matching behavior is reused. No generated word timestamps or replacement of radial/ripple layouts.
- Model migration and backup restoration of the optional receipt should also be checked against a copy of a real device collection before release.
- MusicBrainz requests are spaced at least 1.1 seconds within this client and use an app-identifying User-Agent without personal contact details. Before public distribution, configure a user-approved project support URL per MusicBrainz guidance. Results are cached for this app session; failures are retryable.
