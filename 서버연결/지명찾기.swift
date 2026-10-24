import Foundation

// 맵박스 지명 찾기로 지도 가운데의 동네 이름, 검색한 장소를 가져옵니다.

enum GeocodeReach {
    case noKey
    case failed
    case ok
}

enum PlaceNameClient {
    /// 공유 세션은 응답이 끝나지 않으면 며칠을 기다릴 수 있습니다. 지명 조회는 여기서 끊습니다.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    enum PlaceKind {
        /// 식당·숙소가 아닌 장소입니다. 화면에 식당이나 숙소라고 적지 않습니다.
        case plain
        case restaurant
        case lodging
    }

    struct Hit: Identifiable {
        var id: String
        var name: String
        var latitude: Double
        var longitude: Double
        var kind: PlaceKind = .plain

        /// 검색어가 식당·숙소이고, 결과 종류도 그럴 때만 그 말을 붙입니다.
        var title: String {
            switch kind {
            case .restaurant: return "\(name) · 식당"
            case .lodging: return "\(name) · 숙소"
            case .plain: return name
            }
        }

        var marker: String {
            switch kind {
            case .restaurant: return "restaurant"
            case .lodging: return "lodging"
            case .plain: return "place"
            }
        }
    }

    /// 동네 이름과 그 위 시·도 이름을 함께 모읍니다. 동네 이름만으로는 제주 글을 거르지 못합니다.
    static func areaLabels(latitude: Double, longitude: Double, token: String) async -> [String] {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return [] }
        guard let url = url("https://api.mapbox.com/search/geocode/v6/reverse", [
            "longitude": "\(longitude)",
            "latitude": "\(latitude)",
            "language": "ko",
            "types": "neighborhood,locality,place,region",
            "access_token": token,
        ]) else { return [] }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = object["features"] as? [[String: Any]] else { return [] }
        var names: [String] = []
        func add(_ raw: Any?) {
            guard let text = raw as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, !names.contains(trimmed) else { return }
            names.append(trimmed)
        }
        for feature in features {
            let properties = feature["properties"] as? [String: Any] ?? [:]
            add(properties["name"])
            add(properties["place_formatted"])
            if let context = properties["context"] as? [String: Any] {
                for item in context.values {
                    add((item as? [String: Any])?["name"])
                }
            }
        }
        return names
    }

    static func reverse(latitude: Double, longitude: Double, token: String) async -> (name: String?, reach: GeocodeReach) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return (nil, .noKey) }
        guard let url = url("https://api.mapbox.com/search/geocode/v6/reverse", [
            "longitude": "\(longitude)",
            "latitude": "\(latitude)",
            "language": "ko",
            "types": "neighborhood,locality,place",
            "access_token": token,
        ]) else { return (nil, .failed) }
        let loaded = await hits(url)
        return (loaded.items.first?.name, loaded.reach)
    }

    static func forward(query: String, latitude: Double, longitude: Double, token: String) async -> (hits: [Hit], reach: GeocodeReach) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return ([], .noKey) }
        guard !trimmed.isEmpty else { return ([], .ok) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        guard let url = URL(string: "https://api.mapbox.com/search/geocode/v6/forward?q=\(encoded)&language=ko&limit=5&proximity=\(longitude),\(latitude)&access_token=\(token)") else {
            return ([], .failed)
        }
        let loaded = await hits(url)
        return (loaded.items, loaded.reach)
    }

    private static func hits(_ url: URL) async -> (items: [Hit], reach: GeocodeReach) {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = object["features"] as? [[String: Any]] else { return ([], .failed) }
        let items: [Hit] = features.compactMap { feature in
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
        return (items, .ok)
    }

    private static func url(_ base: String, _ query: [String: String]) -> URL? {
        var parts = URLComponents(string: base)
        parts?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts?.url
    }
}
