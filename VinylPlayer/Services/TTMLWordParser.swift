import Foundation

/// AMLL TTML word spans. Translation/romanization are separate tracks, not words.
final class TTMLWordParser: NSObject, XMLParserDelegate {
    private var result: [LyricLine] = []
    private var depth = 0
    private var excludedDepth: Int?
    private var lineStart: Double?
    private var lineEnd: Double?
    private var lineText = ""
    private var words: [SyncedLyricWord] = []
    private var wordStart: Double?
    private var wordEnd: Double?
    private var wordDepth: Int?
    private var wordText = ""

    static func parse(_ data: Data) -> [LyricLine] {
        let delegate = TTMLWordParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.result.sorted { $0.startTime < $1.startTime }
    }
    static func time(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let value: Double?
        if raw.hasSuffix("ms") { value = Double(raw.dropLast(2)).map { $0 / 1000 } }
        else if raw.hasSuffix("s") { value = Double(raw.dropLast()) }
        else {
            let parts = raw.split(separator: ":").compactMap { Double($0) }
            value = parts.count == raw.split(separator: ":").count && !parts.isEmpty ? parts.reduce(0) { $0 * 60 + $1 } : nil
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        depth += 1
        guard excludedDepth == nil else { return }
        let role = attributes["ttm:role"] ?? attributes["role"] ?? ""
        if role.contains("translation") || role.contains("roman") || role == "x-bg" { excludedDepth = depth; return }
        if elementName == "p" {
            lineStart = Self.time(attributes["begin"]); lineEnd = Self.time(attributes["end"])
            lineText = ""; words = []
        } else if elementName == "span", lineStart != nil, wordDepth == nil,
                  let start = Self.time(attributes["begin"]), let end = Self.time(attributes["end"]), end >= start {
            wordStart = start; wordEnd = end; wordDepth = depth; wordText = ""
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard excludedDepth == nil, lineStart != nil else { return }
        if wordDepth != nil { wordText += string }
        else if !string.contains("\n") && !string.contains("\r") {
            lineText += string
            if !words.isEmpty, !string.isEmpty {
                let last = words.removeLast()
                words.append(.init(text: last.text + string, startMs: last.startMs, durationMs: last.durationMs))
            }
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { depth -= 1 }
        if excludedDepth == depth { excludedDepth = nil; return }
        guard excludedDepth == nil else { return }
        if wordDepth == depth, let start = wordStart, let end = wordEnd {
            lineText += wordText
            words.append(.init(text: wordText, startMs: Int(start * 1000), durationMs: Int((end - start) * 1000)))
            wordDepth = nil; wordStart = nil; wordEnd = nil
        }
        if elementName == "p", let start = lineStart, !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Untimed text must not acquire fabricated word timing.
            let complete = words.map(\.text).joined() == lineText
            result.append(.init(startTime: start, endTime: lineEnd, text: lineText, words: complete ? words : [], source: "AMLL TTML"))
            lineStart = nil
        }
    }
}
