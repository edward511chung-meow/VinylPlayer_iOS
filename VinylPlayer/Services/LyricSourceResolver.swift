import Foundation
import zlib

/// Native iOS adapters for Lyrimuse collector's sources (see ThirdParty/Lyrimuse).
/// A source only contributes word timing when its response actually contains it.
struct LyricSourceResolver {
    struct Query: Sendable {
        let title: String
        let artist: String
        let album: String?
        let duration: Double?
        var search: String { title + " " + artist }
    }
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    typealias JSON = [String: Any]

    func resolve(_ q: Query) async -> [LyricLine] {
        await withTaskGroup(of: (Int, [LyricLine]).self) { group in
            for index in 0..<8 {
                group.addTask {
                    let lines: [LyricLine]
                    switch index {
                    case 0: lines = await netease(q)
                    case 1: lines = await qq(q)
                    case 2: lines = await kugou(q)
                    case 3: lines = await musixmatch(q)
                    case 4: lines = await lrclib(q)
                    case 5: lines = await kuwo(q)
                    case 6: lines = await migu(q)
                    default: lines = await youtube(q)
                    }
                    return (index, lines)
                }
            }
            var results: [(Int, [LyricLine])] = []
            for await result in group where !result.1.isEmpty { results.append(result) }
            // Stable source priority; never let network completion order choose lyrics.
            return results.sorted {
                let a = $0.1.filter { !$0.words.isEmpty }.count
                let b = $1.1.filter { !$0.words.isEmpty }.count
                if (a > 0) != (b > 0) { return a > 0 }
                return $0.0 < $1.0
            }.first?.1 ?? []
        }
    }

    func data(_ endpoint: String, _ params: [String: String] = [:], referer: String? = nil, body: JSON? = nil) async -> Data? {
        guard !Task.isCancelled, var url = URLComponents(string: endpoint), url.scheme == "https" else { return nil }
        if !params.isEmpty { url.queryItems = params.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) } }
        guard let address = url.url else { return nil }
        var request = URLRequest(url: address, timeoutInterval: 8)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4 * 1024 * 1024 else { return nil }
        return data
    }
    func json(_ endpoint: String, _ params: [String: String] = [:], referer: String? = nil, body: JSON? = nil) async -> JSON {
        guard let bytes = await data(endpoint, params, referer: referer, body: body) else { return [:] }
        if let value = try? JSONSerialization.jsonObject(with: bytes) as? JSON { return value }
        // QQ's legacy endpoint can return JSONP.
        guard let string = String(data: bytes, encoding: .utf8), let first = string.firstIndex(of: "{"), let last = string.lastIndex(of: "}"),
              let clean = String(string[first...last]).data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: clean) as? JSON) ?? [:]
    }
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    static func matches(_ q: Query, title: String, artist: String, duration: Double = 0) -> Bool {
        let t = normalized(title), a = normalized(artist), wanted = normalized(q.artist)
        guard !t.isEmpty, t == normalized(q.title), !a.isEmpty, !wanted.isEmpty,
              a == wanted || a.contains(wanted) || wanted.contains(a) else { return false }
        if let d = q.duration, d > 0, duration > 0, abs(d - duration) > 6 { return false }
        return true
    }
    func lrc(_ raw: String?, source: String) -> [LyricLine] {
        LyricLine.fromLRC(raw ?? "").map { line in var copy = line; copy.source = source; return copy }
    }
    func names(_ rows: Any?) -> String { (rows as? [JSON] ?? []).compactMap { $0["name"] as? String }.joined(separator: "/") }
    func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
    func identifier(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }

    func amll(_ id: String, folder: String) async -> [LyricLine] {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }),
              let bytes = await data("https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/\(folder)/\(id).ttml") else { return [] }
        return TTMLWordParser.parse(bytes)
    }
    func netease(_ q: Query) async -> [LyricLine] {
        let root = await json("https://music.163.com/api/search/get", ["s": q.search, "type": "1", "limit": "8", "offset": "0"], referer: "https://music.163.com")
        let songs = (root["result"] as? JSON)?["songs"] as? [JSON] ?? []
        for song in songs where Self.matches(q, title: song["name"] as? String ?? "", artist: names(song["artists"] ?? song["ar"]), duration: number(song["duration"] ?? song["dt"]) / 1000) {
            let id = identifier(song["id"])
            let rich = await json("https://music.163.com/api/song/lyric/v1", ["id": id, "yv": "-1", "lv": "-1"], referer: "https://music.163.com")
            let words = TimedLyricParser.words((rich["yrc"] as? JSON)?["lyric"] as? String ?? "", source: "NetEase YRC")
            if !words.isEmpty { return words }
            let community = await amll(id, folder: "ncm-lyrics")
            if !community.isEmpty { return community }
            let plain = await json("https://music.163.com/api/song/lyric", ["id": id, "lv": "-1", "kv": "-1", "tv": "-1"], referer: "https://music.163.com")
            let lines = lrc((plain["lrc"] as? JSON)?["lyric"] as? String, source: "NetEase")
            if !lines.isEmpty { return lines }
        }
        return []
    }
    func qq(_ q: Query) async -> [LyricLine] {
        let root = await json("https://c.y.qq.com/soso/fcgi-bin/client_search_cp", ["format": "json", "new_json": "1", "t": "0", "aggr": "1", "cr": "1", "p": "1", "n": "8", "w": q.search], referer: "https://y.qq.com")
        let songs = ((root["data"] as? JSON)?["song"] as? JSON)?["list"] as? [JSON] ?? []
        for song in songs where Self.matches(q, title: song["title"] as? String ?? song["songname"] as? String ?? "", artist: names(song["singer"]), duration: number(song["interval"])) {
            let community = await amll(identifier(song["id"] ?? song["songid"]), folder: "qq-lyrics")
            if !community.isEmpty { return community }
            let root = await json("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg", ["format": "json", "nobase64": "1", "g_tk": "5381", "songmid": identifier(song["mid"] ?? song["songmid"])], referer: "https://y.qq.com")
            let lines = lrc(root["lyric"] as? String, source: "QQ Music")
            if !lines.isEmpty { return lines }
        }
        return []
    }
    func kugou(_ q: Query) async -> [LyricLine] {
        let root = await json("https://mobilecdn.kugou.com/api/v3/search/song", ["format": "json", "keyword": q.search, "page": "1", "pagesize": "8", "showtype": "1"])
        let songs = (root["data"] as? JSON)?["info"] as? [JSON] ?? []
        for song in songs where Self.matches(q, title: song["songname"] as? String ?? "", artist: song["singername"] as? String ?? "", duration: number(song["duration"])) {
            let root = await json("https://krcs.kugou.com/search", ["ver": "1", "man": "yes", "client": "mobi", "keyword": q.search, "duration": String(Int(number(song["duration"]) * 1000)), "hash": identifier(song["hash"])])
            guard let candidate = (root["candidates"] as? [JSON])?.first else { continue }
            var params = ["ver": "1", "client": "pc", "id": identifier(candidate["id"]), "accesskey": identifier(candidate["accesskey"]), "fmt": "krc", "charset": "utf8"]
            let rich = await json("https://lyrics.kugou.com/download", params)
            if let raw = Self.decodeKRC(rich["content"] as? String ?? "") {
                let lines = TimedLyricParser.words(raw, relative: true, source: "Kugou KRC")
                if !lines.isEmpty { return lines }
            }
            params["fmt"] = "lrc"
            let plain = await json("https://lyrics.kugou.com/download", params)
            if let bytes = Data(base64Encoded: plain["content"] as? String ?? "") {
                let lines = lrc(String(data: bytes, encoding: .utf8), source: "Kugou")
                if !lines.isEmpty { return lines }
            }
        }
        return []
    }
    static func decodeKRC(_ value: String) -> String? {
        guard let bytes = Data(base64Encoded: value), bytes.starts(with: Data("krc1".utf8)) else { return nil }
        let key: [UInt8] = [0x40,0x47,0x61,0x77,0x5E,0x32,0x74,0x47,0x51,0x36,0x31,0x2D,0xCE,0xD2,0x6E,0x69]
        let compressed = bytes.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % key.count] }
        var output = [UInt8](repeating: 0, count: 4 * 1024 * 1024)
        var size = uLongf(output.count)
        guard uncompress(&output, &size, compressed, uLong(compressed.count)) == Z_OK else { return nil }
        return String(bytes: output.prefix(Int(size)), encoding: .utf8)
    }
    func lrclib(_ q: Query) async -> [LyricLine] {
        var params = ["track_name": q.title, "artist_name": q.artist]
        if let album = q.album { params["album_name"] = album }
        if let duration = q.duration { params["duration"] = String(Int(duration)) }
        let root = await json("https://lrclib.net/api/get", params)
        return lrc(root["syncedLyrics"] as? String, source: "LRCLIB")
    }
    func kuwo(_ q: Query) async -> [LyricLine] {
        let root = await json("https://search.kuwo.cn/r.s", ["all": q.search, "ft": "music", "itemset": "web_2013", "client": "kt", "pn": "0", "rn": "8", "rformat": "json", "encoding": "utf8", "pcjson": "1"], referer: "https://www.kuwo.cn")
        for song in root["abslist"] as? [JSON] ?? [] where Self.matches(q, title: song["SONGNAME"] as? String ?? "", artist: song["ARTIST"] as? String ?? "", duration: number(song["DURATION"])) {
            let root = await json("https://kuwo.cn/openapi/v1/www/lyric/getlyric", ["musicId": identifier(song["MUSICRID"]).replacingOccurrences(of: "MUSIC_", with: "")], referer: "https://www.kuwo.cn")
            let rows = (root["data"] as? JSON)?["lrclist"] as? [JSON] ?? []
            let lines = rows.compactMap { row -> LyricLine? in
                guard let text = row["lineLyric"] as? String else { return nil }
                return LyricLine(startTime: number(row["time"]), endTime: nil, text: text, source: "Kuwo")
            }
            if !lines.isEmpty { return lines }
        }
        return []
    }
    func migu(_ q: Query) async -> [LyricLine] {
        let root = await json("https://pd.musicapp.migu.cn/MIGUM2.0/v1.0/content/search_all.do", ["text": q.search, "pageNo": "1", "pageSize": "8", "searchSwitch": "{\"song\":1}", "isCorrect": "1"], referer: "https://m.music.migu.cn")
        for song in (root["songResultData"] as? JSON)?["result"] as? [JSON] ?? [] where Self.matches(q, title: song["name"] as? String ?? "", artist: names(song["singers"])) {
            guard let url = song["lyricUrl"] as? String, let bytes = await data(url.replacingOccurrences(of: "http://", with: "https://")) else { continue }
            let lines = lrc(String(data: bytes, encoding: .utf8), source: "Migu")
            if !lines.isEmpty { return lines }
        }
        return []
    }
    func musixmatch(_ q: Query) async -> [LyricLine] {
        let base = "https://apic-appmobile.musixmatch.com/ws/1.1/"
        func body(_ json: JSON) -> JSON {
            guard let message = json["message"] as? JSON, number((message["header"] as? JSON)?["status_code"]) == 200 else { return [:] }
            return message["body"] as? JSON ?? [:]
        }
        let tokenResponse = await json(base + "token.get", ["app_id": "mac-ios-v2.0", "user_language": "en"])
        guard let token = body(tokenResponse)["user_token"] as? String, !token.isEmpty else { return [] }
        let auth = ["app_id": "mac-ios-v2.0", "usertoken": token]
        let search = await json(base + "track.search", auth.merging(["q_track": q.title, "q_artist": q.artist, "page_size": "5", "page": "1", "s_track_rating": "desc"]) { _, b in b })
        for row in body(search)["track_list"] as? [JSON] ?? [] {
            guard let song = row["track"] as? JSON, Self.matches(q, title: song["track_name"] as? String ?? "", artist: song["artist_name"] as? String ?? "", duration: number(song["track_length"])) else { continue }
            let params = auth.merging(["track_id": identifier(song["track_id"])]) { _, b in b }
            let rich = await json(base + "track.richsync.get", params)
            if let raw = (body(rich)["richsync"] as? JSON)?["richsync_body"] as? String,
               let bytes = raw.data(using: .utf8) {
                let lines = Self.richsync(bytes)
                if !lines.isEmpty { return lines }
            }
            let plain = await json(base + "track.subtitle.get", params.merging(["subtitle_format": "lrc"]) { _, b in b })
            let lines = lrc((body(plain)["subtitle"] as? JSON)?["subtitle_body"] as? String, source: "Musixmatch")
            if !lines.isEmpty { return lines }
        }
        return []
    }
    static func richsync(_ bytes: Data) -> [LyricLine] {
        struct Word: Decodable { let c: String; let o: Double }
        struct Line: Decodable { let ts: Double; let te: Double; let l: [Word] }
        guard let rows = try? JSONDecoder().decode([Line].self, from: bytes) else { return [] }
        return rows.compactMap { line in
            guard line.ts.isFinite, line.te.isFinite, line.ts >= 0, line.te >= line.ts, line.te <= 86400, !line.l.isEmpty,
                  line.l.allSatisfy({ $0.o.isFinite && $0.o >= 0 && $0.o <= line.te - line.ts }) else { return nil }
            let words = line.l.enumerated().map { i, word in
                let start = line.ts + word.o
                let end = i + 1 < line.l.count ? line.ts + line.l[i + 1].o : line.te
                return SyncedLyricWord(text: word.c, startMs: Int(start * 1000), durationMs: Int(max(0, end - start) * 1000))
            }
            return LyricLine(startTime: line.ts, endTime: line.te, text: words.map(\.text).joined(), words: words, source: "Musixmatch Richsync")
        }
    }
    func youtube(_ q: Query) async -> [LyricLine] {
        func nodes(_ value: Any, key: String) -> [JSON] {
            if let map = value as? JSON { return (map[key] as? JSON).map { [$0] } ?? map.values.flatMap { nodes($0, key: key) } }
            return (value as? [Any] ?? []).flatMap { nodes($0, key: key) }
        }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let web: JSON = ["clientName": "WEB_REMIX", "clientVersion": "1." + formatter.string(from: Date()) + ".01.00"]
        func post(_ action: String, _ values: JSON, mobile: Bool = false) async -> JSON {
            let client: JSON = mobile ? ["clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50"] : web
            return await json("https://music.youtube.com/youtubei/v1/" + action, referer: "https://music.youtube.com", body: values.merging(["context": ["client": client]]) { _, b in b })
        }
        let search = await post("search", ["query": q.search, "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"])
        for item in nodes(search, key: "musicResponsiveListItemRenderer") {
            let columns = item["flexColumns"] as? [JSON] ?? []
            let texts = columns.map { col in ((col["musicResponsiveListItemFlexColumnRenderer"] as? JSON)?["text"] as? JSON)?["runs"] as? [JSON] ?? [] }
            guard texts.count >= 2 else { continue }
            let title = texts[0].compactMap { $0["text"] as? String }.joined()
            let artist = texts[1].compactMap { $0["text"] as? String }.joined()
            guard Self.matches(q, title: title, artist: artist), let video = (item["playlistItemData"] as? JSON)?["videoId"] as? String else { continue }
            let next = await post("next", ["videoId": video, "playlistId": "RDAMVM" + video, "isAudioOnly": true])
            for endpoint in nodes(next, key: "browseEndpoint") {
                let config = endpoint["browseEndpointContextSupportedConfigs"] as? JSON
                guard (config?["browseEndpointContextMusicConfig"] as? JSON)?["pageType"] as? String == "MUSIC_PAGE_TYPE_TRACK_LYRICS", let id = endpoint["browseId"] as? String else { continue }
                let browse = await post("browse", ["browseId": id], mobile: true)
                func timed(_ value: Any) -> [JSON] {
                    if let map = value as? JSON { if let rows = map["timedLyricsData"] as? [JSON] { return rows }; return map.values.flatMap(timed) }
                    return (value as? [Any] ?? []).flatMap(timed)
                }
                return timed(browse).compactMap { row in
                    guard let text = row["lyricLine"] as? String, let cue = row["cueRange"] as? JSON else { return nil }
                    return LyricLine(startTime: number(cue["startTimeMilliseconds"]) / 1000, endTime: number(cue["endTimeMilliseconds"]) / 1000, text: text, source: "LyricFind / YouTube Music")
                }
            }
        }
        return []
    }
}
