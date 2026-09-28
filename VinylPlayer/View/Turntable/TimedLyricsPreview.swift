#if DEBUG
import SwiftUI

/// No account or audio playback needed. Scrub to inspect soft word fill and rise.
private struct TimedLyricsPreview: View {
    @State private var position = 1.4
    private let words = [
        SyncedLyricWord(text: "Hello ", startMs: 1000, durationMs: 800),
        SyncedLyricWord(text: "world ", startMs: 1800, durationMs: 800),
        SyncedLyricWord(text: "again", startMs: 2600, durationMs: 1000)
    ]
    var body: some View {
        let anchor = LyricPlaybackAnchor(position: position, date: .now, isPlaying: false)
        VStack(spacing: 32) {
            KaraokeLyricText(
                text: "Hello world again", fillProgress: 0.4, markerFillProgress: 1,
                fontSize: 32, weight: .bold, filledColor: .black,
                unfilledColor: .gray, maxWidth: 320, showsHandwrittenHighlight: true,
                words: words, playbackAnchor: anchor, nextLineStartMs: 3400
            )
            CurvedKaraokeText(
                text: "Hello world again", radius: 240, centerX: -32, centerY: 200,
                centerAngle: 0, fontSize: 32, weight: .bold,
                fillProgress: 0.4, markerFillProgress: 1,
                words: words, playbackAnchor: anchor, nextLineStartMs: 3400
            )
            .frame(height: 400)
            Slider(value: $position, in: 0...3.4)
            Text("\(position, specifier: "%.2f") s").monospacedDigit()
        }
        .padding(32)
        .background(Color(red: 0.84, green: 0.75, blue: 0.8))
    }
}
#Preview("Lyrimuse word timing — existing markers") {
    TimedLyricsPreview()
}
#endif
