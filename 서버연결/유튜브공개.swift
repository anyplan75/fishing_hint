import Foundation

// 기준점의 지역 이름으로 유튜브 공개 영상만 찾습니다.
// 로그인, 비공개 영상, 영상 페이지 안쪽은 보지 않습니다. 제목과 설명만 읽습니다.

enum YouTubePublicClient {
    static func search(region: String, apiKey: String) async -> [PublicFishingNote] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, region.count >= 2 else { return [] }
        let query = region.contains("낚시") ? region : "\(region) 낚시"
        guard var parts = URLComponents(string: "https://www.googleapis.com/youtube/v3/search") else { return [] }
        parts.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "8"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "regionCode", value: "KR"),
            URLQueryItem(name: "relevanceLanguage", value: "ko"),
        ]
        guard let url = parts.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return [] }
        var notes: [PublicFishingNote] = []
        for item in items {
            guard let note = note(from: item, region: region) else { continue }
            notes.append(note)
            if notes.count == 8 { break }
        }
        return notes
    }

    private static func note(from item: [String: Any], region: String) -> PublicFishingNote? {
        let identity = item["id"] as? [String: Any] ?? [:]
        guard let videoID = identity["videoId"] as? String, !videoID.isEmpty,
              let pageURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return nil }
        let snippet = item["snippet"] as? [String: Any] ?? [:]
        let title = plain(snippet["title"] as? String)
        let detail = plain(snippet["description"] as? String)
        guard title.count >= 2 else { return nil }
        let summary = detail.isEmpty ? title : "\(title). \(detail)"
        return PublicFishingNote(
            id: "youtube-\(videoID)",
            sourceName: "유튜브",
            pageURL: pageURL,
            writtenAt: nil,
            hasClock: false,
            summary: String(summary.prefix(180)),
            placeLabel: region
        )
    }

    private static func plain(_ raw: String?) -> String {
        guard var text = raw else { return "" }
        text = text.replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
