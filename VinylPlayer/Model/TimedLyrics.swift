import Foundation

/// Absolute word timing, using Lyrimuse's millisecond representation.
struct SyncedLyricWord: Codable, Equatable, Sendable {
    let text: String
    let startMs: Int
    let durationMs: Int
}

struct SyncedLyricWordGroup {
    let words: [SyncedLyricWord]
    var startMs: Int { words.first?.startMs ?? 0 }
    var endMs: Int { words.last.map { $0.startMs + $0.durationMs } ?? 0 }
}

struct LyricLine: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let text: String
    var words: [SyncedLyricWord] = []
    var source: String? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startTime == rhs.startTime && lhs.endTime == rhs.endTime && lhs.text == rhs.text
            && lhs.words == rhs.words && lhs.source == rhs.source
    }

    /// Plain LRC remains readable by existing tools; a versioned sidecar keeps
    /// true word times/source across SwiftData, export and in-memory caching.
    static func toLRC(_ lines: [LyricLine]) -> String {
        let plain = lines.map { line in
            let ms = max(0, Int((line.startTime * 1000).rounded()))
            return String(format: "[%02d:%02d.%03d] %@", ms / 60000, ms / 1000 % 60, ms % 1000, line.text)
        }.joined(separator: "\n")
        guard lines.contains(where: { !$0.words.isEmpty }),
              let data = try? JSONEncoder().encode(lines) else { return plain }
        return "[vpwords:v1:\(data.base64EncodedString())]\n" + plain
    }

    static func fromLRC(_ content: String) -> [LyricLine] {
        if let first = content.components(separatedBy: .newlines).first,
           first.hasPrefix("[vpwords:v1:"), first.hasSuffix("]"),
           let data = Data(base64Encoded: String(first.dropFirst(12).dropLast())),
           let lines = try? JSONDecoder().decode([LyricLine].self, from: data),
           lines.allSatisfy({ $0.startTime.isFinite && $0.words.allSatisfy { $0.startMs >= 0 && $0.durationMs >= 0 } }) {
            return lines
        }
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#)
        var lines: [LyricLine] = []
        var offset = 0.0
        for raw in content.components(separatedBy: .newlines) {
            if raw.hasPrefix("[offset:"), let value = Double(raw.dropFirst(8).dropLast()) { offset = value / 1000 }
            let ns = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let fraction = match.range(at: 3).location == NSNotFound ? "0" : ns.substring(with: match.range(at: 3))
                let time = (Double(ns.substring(with: match.range(at: 1))) ?? 0) * 60
                    + (Double(ns.substring(with: match.range(at: 2))) ?? 0)
                    + (Double("0." + fraction) ?? 0)
                lines.append(LyricLine(startTime: max(0, time + offset), endTime: nil, text: text))
            }
        }
        lines.sort { $0.startTime < $1.startTime }
        return lines.enumerated().map { index, line in
            LyricLine(startTime: line.startTime, endTime: index + 1 < lines.count ? lines[index + 1].startTime : nil,
                      text: line.text)
        }
    }
}

/// Immutable playback anchor sampled by the word renderer, rather than an
/// animation repeatedly retargeted by coarse music-service samples.
struct LyricPlaybackAnchor: Equatable {
    var position: TimeInterval
    var date: Date
    var isPlaying: Bool
    func milliseconds(at now: Date) -> Int {
        Int(max(0, position + (isPlaying ? max(0, now.timeIntervalSince(date)) : 0)) * 1000)
    }
}

enum TimedLyricParser {
    /// YRC times are absolute; KRC offsets are relative to the line start.
    static func words(_ raw: String, relative: Bool = false, source: String) -> [LyricLine] {
        let head = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
        let token = try! NSRegularExpression(pattern: relative ? #"<(\d+),(\d+),\d+>"# : #"\((\d+),(\d+),\d+\)"#)
        var result: [LyricLine] = []
        for line in raw.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let h = head.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let start = Int(ns.substring(with: h.range(at: 1))), let duration = Int(ns.substring(with: h.range(at: 2))), start <= 86_400_000, duration <= 86_400_000 else { continue }
            let matches = token.matches(in: line, range: NSRange(location: NSMaxRange(h.range), length: ns.length - NSMaxRange(h.range)))
            let words = matches.enumerated().compactMap { index, match -> SyncedLyricWord? in
                guard let offset = Int(ns.substring(with: match.range(at: 1))), let length = Int(ns.substring(with: match.range(at: 2))), offset <= 86_400_000, length <= 86_400_000 else { return nil }
                let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let text = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
                return SyncedLyricWord(text: text, startMs: offset + (relative ? start : 0), durationMs: length)
            }
            guard words.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            result.append(LyricLine(startTime: Double(start) / 1000, endTime: Double(start + duration) / 1000,
                                    text: words.map(\.text).joined(), words: words, source: source))
        }
        return result.sorted { $0.startTime < $1.startTime }
    }
}
