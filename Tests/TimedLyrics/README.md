Run from the project root (no account/network required):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path /tmp/vinyl-swift-module-cache VinylPlayer/Model/TimedLyrics.swift VinylPlayer/Model/LyrimuseKaraoke.swift VinylPlayer/Services/TTMLWordParser.swift VinylPlayer/Services/LyricSourceResolver.swift Tests/TimedLyrics/main.swift -o /tmp/vinyl-timed-lyrics-check
/tmp/vinyl-timed-lyrics-check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path /tmp/vinyl-swift-module-cache VinylPlayer/Model/TimedLyrics.swift VinylPlayer/Services/TTMLWordParser.swift VinylPlayer/Services/LyricSourceResolver.swift Tests/TimedLyrics/SourceSelection.swift -o /tmp/vinyl-source-selection-check
/tmp/vinyl-source-selection-check
```

Xcode visual entry: `VinylPlayer/View/Turntable/TimedLyricsPreview.swift`.
Scrub the slider: the marker stays fixed; glyph fill and drawing offset change.
Synthetic text is used so this check does not depend on music catalog access.
