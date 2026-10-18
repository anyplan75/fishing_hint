import Foundation

// 맵박스 지명 찾기로 지도 가운데의 동네 이름, 검색한 장소를 가져옵니다.

enum PlaceNameClient {
    struct Hit: Identifiable {
        var id: String
        var name: String
        var latitude: Double
        var longitude: Double
    }

    static func reverse(latitude: Double, longitude: Double, token: String) async -> String? {
        guard !token.isEmpty else { return nil }
        guard let url = url("https://api.mapbox.com/search/geocode/v6/reverse", [
            "longitude": "\(longitude)",
            "latitude": "\(latitude)",
            "language": "ko",
            "types": "neighborhood,locality,place",
            "access_token": token,
        ]) else { return nil }
        return await hits(url).first?.name
    }

    static func forward(query: String, latitude: Double, longitude: Double, token: String) async -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !trimmed.isEmpty else { return [] }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        guard let url = URL(string: "https://api.mapbox.com/search/geocode/v6/forward?q=\(encoded)&language=ko&limit=5&proximity=\(longitude),\(latitude)&access_token=\(token)") else {
            return []
        }
        return await hits(url)
    }

    private static func hits(_ url: URL) async -> [Hit] {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = object["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { feature in
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let geometry = feature["geometry"] as? [String: Any] ?? [:]
            let coordinates = geometry["coordinates"] as? [Double] ?? []
            guard coordinates.count >= 2 else { return nil }
            let name = (properties["name"] as? String)
                ?? (properties["full_address"] as? String)
                ?? "이름 없는 장소"
            let id = (properties["mapbox_id"] as? String) ?? name
            return Hit(id: id, name: name, latitude: coordinates[1], longitude: coordinates[0])
        }
    }

    private static func url(_ base: String, _ query: [String: String]) -> URL? {
        var parts = URLComponents(string: base)
        parts?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts?.url
    }
}
