# VinylPlayer for iOS

A vinyl-inspired music player for iPhone and iPad, built with SwiftUI. Browse your album collection with Cover Flow, follow animated lyrics, and connect to Apple Music or Spotify.

This project is under active development. Playback and online content depend on service authorization, account access, subscriptions, region, and track availability. This repository does not include music files or service credentials.

## Features

- **Vinyl playback interface**: turntable and tonearm visuals, playback progress, appearance themes, and app icons.
- **Album collection**: grid, stacked, and Cover Flow browsing, music library imports, favorites, and playlists.
- **Playback controls**: playback queue, shuffle and repeat, lock screen controls, widgets, and Live Activities.
- **Discovery and search**: local collection search, Apple Music and Spotify catalog search, and recommendations based on listening history.
- **Lyrics**: line and word timing, multiple lyric sources, TTML parsing, and several presentation styles.
- **Metadata enrichment**: MusicBrainz and Cover Art Archive matching, plus metadata, artwork, and LRC files from local album folders.
- **Everyday tools**: JSON backup and merge-based restore, a sleep timer, listening statistics, and share cards and videos.

## Development Environment

- macOS with a full Xcode installation. **Xcode 27.0** was used when preparing this repository.
- The app and widget targets have an **iOS 26.0** deployment target. The project-level setting is 26.5; target settings take precedence.
- Swift, SwiftUI, SwiftData, MusicKit, WidgetKit, and ActivityKit.
- Xcode resolves dependencies through Swift Package Manager. The committed `Package.resolved` pins Spotify iOS SDK 1.2.5 and ScreenCorners 1.0.1.

## Getting Started

```sh
git clone https://github.com/edward511chung-meow/VinylPlayer_iOS.git
cd VinylPlayer_iOS
open VinylPlayer.xcodeproj
```

1. Wait for Xcode to resolve the Swift packages.
2. Select the **VinylPlayer** scheme and a supported iOS Simulator.
3. Click **Run**. To install on a physical device, select your development team and configure available bundle identifiers under **Signing & Capabilities** for both the app and widget targets.
4. If you change the App Group, update both targets' entitlements and all references to `group.com.Vinylplayer.shared` in the source code so the widgets can continue sharing data with the app.

### Music Service Configuration

Service configuration is defined in [`APIConfig.swift`](VinylPlayer/Networking/APIConfig.swift).

- **Apple Music**: access uses system authorization and MusicKit. Verify account permissions, library access, and playback on a physical device.
- **Spotify**: use your own Spotify application client ID and register the redirect URI `vinylplayer://spotify-callback`. The client ID is a public application identifier. Do not commit client secrets or access and refresh tokens. App Remote features require Spotify to be installed on the device and valid authorization.
- **Discogs**: credentials are empty by default. Requests currently use `personalAccessToken` for authorization. Configure the token locally and remove its actual value before committing.
- **MusicBrainz / Cover Art Archive**: no API key is required. Service availability and request limits still apply.

The `.gitignore` excludes common secret files, but it does not exclude credentials written directly into Swift source files.

## Building and Verification

Build for the Simulator without code signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project VinylPlayer.xcodeproj \
  -scheme VinylPlayer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/VinylPlayer-DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The existing tests are standalone Swift harnesses, rather than a unified XCTest suite:

- [Lyric parsing and source selection tests](Tests/TimedLyrics/README.md): includes commands for running the tests offline.
- [Library and playback verification](Docs/LibraryPlaybackVerification.md)
- [Home, search, backup, and sleep timer verification](Docs/HomeSearchUtilitiesVerification.md)
- [Album metadata enrichment verification](Docs/AlbumEnrichmentVerification.md)

These documents record verification performed during feature implementation and its limitations. They do not imply that every check has been rerun for every commit.

### UI Previews Without a Music Account

Open `HomeDesignPreview.swift` or `TimedLyricsPreview.swift` in Xcode Preview. Alternatively, enable one of these launch arguments under the scheme's **Run → Arguments Passed On Launch** settings:

```text
--home-design-preview
--library-design-preview
--search-design-preview
--backup-design-preview
--sleep-design-preview
--metadata-design-preview
```

These Debug entry points use isolated in-memory data. Actual playback, background track transitions, widget controls, and service sign-in still require verification with a physical device and music service accounts.

## Project Structure

| Path | Contents |
| --- | --- |
| `VinylPlayer/` | App entry points, SwiftData models, services, SwiftUI views, and assets |
| `VinylPlayerWidgets/` | Widgets, Live Activities, and playback intents |
| `VinylPlayer.xcodeproj/` | Xcode project, shared schemes, and dependency lockfile |
| `Tests/` | Standalone test harnesses |
| `Docs/` | Feature verification records and manual checks |
| `Design/` | App icon design assets, generation records, and processing tools |
| `ThirdParty/` | Third-party notices and full license texts |

## Known Limitations

- Apple Music system playback currently requires tracks that can be resolved in the device's music library. Continuous background playback across services depends on each provider's capabilities.
- The sleep timer is best effort. If the app is suspended, stopping playback may be delayed until execution resumes.
- Backups do not include music files, login credentials, or settings. Local folder reading enriches existing track metadata and does not import audio.
- Lyrics, artwork, and online catalog entries may be missing or become unavailable when upstream sources change.

## Third-Party Code and Licensing

The origin and scope of the Lyrimuse-derived code are documented in [`ThirdParty/Lyrimuse/NOTICE.md`](ThirdParty/Lyrimuse/NOTICE.md). Its full [GPL-3.0 license](ThirdParty/Lyrimuse/LICENSE) is included. Spotify iOS SDK and ScreenCorners are provided under their respective upstream licenses.

No separate license has been specified for the original portions of this project. Existing third-party licenses continue to apply.
