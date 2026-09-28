import Foundation

private final class FixtureProtocol: URLProtocol {
    static var wrongArtist = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let body: [String: Any]
        if url.host == "music.163.com", url.path.contains("search") {
            body = ["result": ["songs": [["id": 123, "name": "Example", "artists": [["name": Self.wrongArtist ? "Other" : "Artist"]], "duration": 200000]]]]
        } else if url.host == "music.163.com", url.path.hasSuffix("v1") {
            body = ["yrc": ["lyric": "[1000,1000](1000,400,0)Hello (1400,600,0)world"]]
        } else if url.host == "lrclib.net" {
            body = ["syncedLyrics": "[00:01.000]Fallback line"]
        } else { body = [:] }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct SourceSelectionCheck {
    static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let resolver = LyricSourceResolver(session: URLSession(configuration: config))
        let q = LyricSourceResolver.Query(title: "Example", artist: "Artist", album: nil, duration: 200)
        let rich = await resolver.resolve(q)
        precondition(rich.first?.words.count == 2 && rich.first?.source == "NetEase YRC")
        print("PASS: real resolver prioritizes word timing over sentence fallback")
        FixtureProtocol.wrongArtist = true
        let fallback = await resolver.resolve(q)
        precondition(fallback.first?.text == "Fallback line" && fallback.first?.words.isEmpty == true)
        print("PASS: mismatched recording rejected and sentence fallback retained")
    }
}
