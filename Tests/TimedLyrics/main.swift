import Foundation
import zlib

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    print("PASS: " + message)
}
let yrc = "[1000,1200](1000,200,0)Hello (1200,1000,0)world\n[2200,800](2200,800,0)Again"
let lines = TimedLyricParser.words(yrc, source: "fixture")
check(lines.count == 2 && lines[0].text == "Hello world", "YRC text including spaces")
check(lines[0].words[1].startMs == 1200, "YRC absolute time")
check(LyricLine.fromLRC(LyricLine.toLRC(lines)) == lines, "word timing survives persistent LRC round trip")
check(LyricLine.fromLRC("[00:01]A\n[00:02.05][00:03.125]B").map(\.startTime) == [1, 2.05, 3.125], "legacy LRC fractions and repeated timestamps")
check(LyricLine.fromLRC("[vpwords:v1:invalid]\n[00:01.00]A").count == 1, "damaged sidecar falls back to LRC")
let krc = "[1000,1200]<0,200,0>Hello <200,1000,0>world"
check(TimedLyricParser.words(krc, relative: true, source: "KRC")[0].words[1].startMs == 1200, "KRC relative time")
let raw = Array(krc.utf8)
var compressed = [UInt8](repeating: 0, count: Int(compressBound(uLong(raw.count))))
var count = uLongf(compressed.count)
check(compress(&compressed, &count, raw, uLong(raw.count)) == Z_OK, "compressed KRC fixture")
let key: [UInt8] = [0x40,0x47,0x61,0x77,0x5E,0x32,0x74,0x47,0x51,0x36,0x31,0x2D,0xCE,0xD2,0x6E,0x69]
let encrypted = Data("krc1".utf8) + Data(compressed.prefix(Int(count)).enumerated().map { $0.element ^ key[$0.offset % 16] })
check(LyricSourceResolver.decodeKRC(encrypted.base64EncodedString()) == krc, "KRC download decoding")
check(LyricSourceResolver.decodeKRC("garbage") == nil, "invalid KRC rejected")
let ttml = """
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div><p begin="1s" end="2.2s"><span begin="1s" end="1.2s">Hello</span> <span begin="1.2s" end="2.2s">world</span><span ttm:role="x-translation">譯文</span></p></div></body></tt>
"""
let tt = TTMLWordParser.parse(Data(ttml.utf8))
check(tt.count == 1 && tt[0].text == "Hello world" && tt[0].words.count == 2, "TTML words, spaces and translation exclusion")
check(TTMLWordParser.time("01:02.125") == 62.125 && TTMLWordParser.time("120ms") == 0.12, "TTML clock formats")
let rich = Data(#"[{"ts":1,"te":2.2,"l":[{"c":"Hello ","o":0},{"c":"world","o":0.2}]}]"#.utf8)
check(LyricSourceResolver.richsync(rich)[0].words[1].startMs == 1200, "Musixmatch richsync word offset")
let short = SyncedLyricWord(text: "a", startMs: 1000, durationMs: 0)
check(KaraokeFill.fillFraction(for: short, atMs: 1040) == 0.5, "zero-length words use 80 ms minimum")
check(KaraokeFill.fillFraction(for: short, atMs: 800) < 0, "future words stay unfilled")
let clamped = KaraokeFill.tailClamped(lines[0].words, nextLineStartMs: 2200)
check(clamped[0] == lines[0].words[0] && clamped[1].durationMs == 860, "only last word shortened before next line")
let fraction = KaraokeFill.fillFraction(for: clamped[1], atMs: 2190)
check(KaraokeFill.stops(left: fraction - 0.08, right: fraction + 0.08).allSatisfy { $0.intensity == 1 }, "last word visibly finished before line change")
let stops = KaraokeFill.stops(left: 0.42, right: 0.58)
check(stops.map(\.location) == [0, 0.42, 0.58, 1], "soft boundary has nonzero width")
let anchor = LyricPlaybackAnchor(position: 2, date: Date(timeIntervalSince1970: 0), isPlaying: false)
check(anchor.milliseconds(at: Date(timeIntervalSince1970: 20)) == 2000, "pause freezes word fill")
let q = LyricSourceResolver.Query(title: "Example (Live)", artist: "Artist", album: nil, duration: 200)
check(!LyricSourceResolver.matches(q, title: "Example", artist: "Artist", duration: 200), "recording version mismatch rejected")
check(!LyricSourceResolver.matches(q, title: "Example (Live)", artist: "Someone else", duration: 200), "wrong artist rejected")
check(!LyricSourceResolver.matches(q, title: "Example (Live)", artist: "Artist", duration: 230), "wrong duration rejected")
print("All timed lyric checks passed")
