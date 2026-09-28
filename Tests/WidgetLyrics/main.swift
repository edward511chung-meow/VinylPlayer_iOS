import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    precondition(value(), label); print("PASS: " + label)
}
let origin = Date(timeIntervalSince1970: 1000)
var data = SharedNowPlayingData.empty
data.trackTitle = "Fixture"
data.duration = 20
data.timestamp = origin
data.isPlaying = true
data.timedLyrics = [.init(startTime: 5, text: "First"), .init(startTime: 10, text: "Second"), .init(startTime: 15, text: "Third")]
check(data.lyricEntryDates(from: origin).map { $0.timeIntervalSince(origin) } == [0, 5, 10, 15, 20], "whole song entries include each sentence and song end")
check(data.projected(at: origin).currentLyric == nil, "intro has no current lyric")
check(data.projected(at: origin.addingTimeInterval(5)).currentLyric == "First", "first sentence appears at its boundary")
let second = data.projected(at: origin.addingTimeInterval(12))
check(second.currentLyric == "Second" && second.previousLyric == "First" && second.nextLyric == "Third", "lyrics advance without a host write")
check(second.currentLyricContextIndex == 1, "context index agrees with current sentence")
check(data.lyricEntryDates(from: origin.addingTimeInterval(12)).map { $0.timeIntervalSince(origin) } == [12, 15, 20], "late reload starts at current lyric, not old snapshot")
var paused = second
paused.isPlaying = false
check(paused.lyricEntryDates(from: origin.addingTimeInterval(14)).count == 1, "pause cancels future sentence entries")
check(paused.projected(at: origin.addingTimeInterval(19)).currentLyric == "Second", "paused lyric freezes")
paused.timestamp = origin.addingTimeInterval(14)
paused.isPlaying = true
check(paused.lyricEntryDates(from: paused.timestamp).map { $0.timeIntervalSince(origin) } == [14, 17, 22], "resume rebases future entries")
var seek = data
seek.timestamp = origin.addingTimeInterval(3)
seek.elapsedTime = 16
check(seek.projected(at: seek.timestamp).currentLyric == "Third", "forward seek updates current sentence")
seek.elapsedTime = 6
check(seek.projected(at: seek.timestamp).currentLyric == "First", "backward seek updates current sentence")
let ended = data.projected(at: origin.addingTimeInterval(30))
check(!ended.isPlaying && ended.elapsedTime == 20, "song end clamps extrapolation")
check(data.lyricEntryDates(from: origin.addingTimeInterval(30)).count == 1, "expired timeline does not loop atEnd")
let encoded = try JSONEncoder().encode(data)
let decoded = try JSONDecoder().decode(SharedNowPlayingData.self, from: encoded)
check(decoded.timedLyrics == data.timedLyrics, "complete schedule survives shared container encoding")
var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy.removeValue(forKey: "timedLyrics")
legacy.removeValue(forKey: "trackIdentity")
let old = try JSONDecoder().decode(SharedNowPlayingData.self, from: JSONSerialization.data(withJSONObject: legacy))
check(old.timedLyrics == nil, "previous app snapshots remain compatible")
