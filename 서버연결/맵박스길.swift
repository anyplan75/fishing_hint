import Foundation

// 맵박스에서 식당·숙소 위치, 가까운 길, 두 지점 사이 길을 가져옵니다.
// 주소는 공식 문서에 있는 것만 씁니다. 키 값은 적지 않습니다.

enum MapboxGuide {
    enum Intent {
        case restaurant
        case hotel
        case lodging
        case plain
    }

    struct Found {
        var hits: [PlaceNameClient.Hit]
        var reach: GeocodeReach
        var note: String
    }

    struct Road {
        var latitude: Double
        var longitude: Double
        var matched: Bool
        var note: String
    }

    struct RouteDraw {
        var line: [[Double]]
        var note: String
    }

    /// 검색어 안에 식당·숙소 말이 있을 때만 그 종류로 봅니다.
    static func intent(of query: String) -> Intent {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hotelWords = ["호텔", "hotel"]
        let lodgingWords = ["숙소", "펜션", "민박", "모텔", "게스트하우스", "lodging"]
        let restaurantWords = ["식당", "맛집", "음식점", "레스토랑", "restaurant"]
        let hotel = hotelWords.contains { text.contains($0) }
        let lodging = lodgingWords.contains { text.contains($0) }
        let restaurant = restaurantWords.contains { text.contains($0) }
        if restaurant && !hotel && !lodging { return .restaurant }
        if hotel && !restaurant { return .hotel }
        if lodging && !restaurant { return .lodging }
        return .plain
    }

    static func search(query: String, latitude: Double, longitude: Double, token: String) async -> Found {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return Found(hits: [], reach: .noKey, note: "지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
        }
        guard !trimmed.isEmpty else { return Found(hits: [], reach: .ok, note: "") }
        switch intent(of: trimmed) {
        case .restaurant:
            return await box(
                q: "restaurant",
                category: "restaurant",
                allowed: .restaurant,
                latitude: latitude,
                longitude: longitude,
                token: token,
                empty: "이 근처에서 식당을 찾지 못했습니다."
            )
        case .hotel:
            return await box(
                q: "hotel",
                category: "lodging",
                allowed: .lodging,
                latitude: latitude,
                longitude: longitude,
                token: token,
                empty: "이 근처에서 숙소를 찾지 못했습니다."
            )
        case .lodging:
            return await box(
                q: "lodging",
                category: "lodging",
                allowed: .lodging,
                latitude: latitude,
                longitude: longitude,
                token: token,
                empty: "이 근처에서 숙소를 찾지 못했습니다."
            )
        case .plain:
            async let named = PlaceNameClient.forward(query: trimmed, latitude: latitude, longitude: longitude, token: token)
            async let places = box(
                q: trimmed,
                category: nil,
                allowed: .plain,
                latitude: latitude,
                longitude: longitude,
                token: token,
                empty: ""
            )
            let geo = await named
            let poi = await places
            var hits = poi.hits
            for item in geo.hits where !hits.contains(where: { same($0, item) }) {
                hits.append(item)
            }
            if hits.isEmpty {
                let reach: GeocodeReach = (geo.reach == .failed && poi.reach == .failed) ? .failed : .ok
                let note = reach == .failed ? "검색 결과를 가져오지 못했습니다." : "그 검색의 위치를 찾지 못했습니다."
                return Found(hits: [], reach: reach, note: note)
            }
            return Found(hits: Array(hits.prefix(8)), reach: .ok, note: "")
        }
    }

    /// 흔들리는 점을 가까운 차도 위에 붙입니다. 길이 없으면 처음 점을 그대로 둡니다.
    static func matchRoad(points: [(longitude: Double, latitude: Double)], token: String) async -> Road {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = points.last else {
            return Road(latitude: 0, longitude: 0, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        guard !token.isEmpty else {
            return Road(latitude: last.latitude, longitude: last.longitude, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        var trace = points
        if trace.count == 1, let only = trace.first {
            trace.append(only)
        }
        let path = trace.map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }.joined(separator: ";")
        let radii = Array(repeating: "50", count: trace.count).joined(separator: ";")
        guard let url = endpoint(
            "https://api.mapbox.com/matching/v5/mapbox/driving/\(path).json",
            [
                URLQueryItem(name: "geometries", value: "geojson"),
                URLQueryItem(name: "overview", value: "full"),
                URLQueryItem(name: "radiuses", value: radii),
                URLQueryItem(name: "access_token", value: token),
            ]
        ) else {
            return Road(latitude: last.latitude, longitude: last.longitude, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        guard let object = await json(url), let code = object["code"] as? String else {
            return Road(latitude: last.latitude, longitude: last.longitude, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        guard code == "Ok", let tracepoints = object["tracepoints"] as? [Any] else {
            return Road(latitude: last.latitude, longitude: last.longitude, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        let index = min(points.count - 1, tracepoints.count - 1)
        let location = (index >= 0 ? doubles((tracepoints[index] as? [String: Any])?["location"]) : [])
        guard location.count >= 2 else {
            return Road(latitude: last.latitude, longitude: last.longitude, matched: false, note: "가까운 길이 없어 원래 위치를 유지합니다.")
        }
        return Road(
            latitude: location[1],
            longitude: location[0],
            matched: true,
            note: "가까운 길에 맞췄습니다."
        )
    }

    /// 현재 위치에서 고른 자리까지 차도 길을 계산합니다.
    static func route(fromLon: Double, fromLat: Double, toLon: Double, toLat: Double, name: String, token: String) async -> RouteDraw {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return RouteDraw(line: [], note: "지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
        }
        let path = String(format: "%.6f,%.6f;%.6f,%.6f", fromLon, fromLat, toLon, toLat)
        guard let url = endpoint(
            "https://api.mapbox.com/directions/v5/mapbox/driving/\(path)",
            [
                URLQueryItem(name: "geometries", value: "geojson"),
                URLQueryItem(name: "overview", value: "full"),
                URLQueryItem(name: "access_token", value: token),
            ]
        ) else {
            return RouteDraw(line: [], note: "길을 가져오지 못했습니다.")
        }
        guard let object = await json(url), let code = object["code"] as? String else {
            return RouteDraw(line: [], note: "길을 가져오지 못했습니다.")
        }
        guard code == "Ok",
              let routes = object["routes"] as? [[String: Any]],
              let geometry = routes.first?["geometry"] as? [String: Any],
              let raw = geometry["coordinates"] as? [Any] else {
            return RouteDraw(line: [], note: reason(for: code))
        }
        let line: [[Double]] = raw.compactMap { item in
            let pair = doubles(item)
            guard pair.count >= 2 else { return nil }
            return [pair[0], pair[1]]
        }
        guard line.count >= 2 else {
            return RouteDraw(line: [], note: "이 두 지점 사이 길이 없습니다.")
        }
        return RouteDraw(line: line, note: "현재 위치에서 \(name)까지 길을 그렸습니다.")
    }

    private static func box(
        q: String,
        category: String?,
        allowed: PlaceNameClient.PlaceKind,
        latitude: Double,
        longitude: Double,
        token: String,
        empty: String
    ) async -> Found {
        // 한국어 질의는 이 통로가 장소를 비워서, 공식 카테고리 검색은 영문 종류 이름으로 부릅니다.
        // 식당·숙소라는 화면 글은 돌아온 종류가 맞을 때만 한국어로 붙입니다.
        var items = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "proximity", value: String(format: "%.6f,%.6f", longitude, latitude)),
            URLQueryItem(name: "types", value: category == nil ? "poi,address" : "poi"),
            URLQueryItem(name: "access_token", value: token),
        ]
        if let category {
            items.append(URLQueryItem(name: "poi_category", value: category))
        }
        guard let url = endpoint("https://api.mapbox.com/search/searchbox/v1/forward", items) else {
            return Found(hits: [], reach: .failed, note: "검색 결과를 가져오지 못했습니다.")
        }
        guard let object = await json(url), let features = object["features"] as? [[String: Any]] else {
            return Found(hits: [], reach: .failed, note: "검색 결과를 가져오지 못했습니다.")
        }
        var hits: [PlaceNameClient.Hit] = []
        for feature in features {
            guard let hit = hit(from: feature, allowed: allowed) else { continue }
            if hits.contains(where: { same($0, hit) }) { continue }
            hits.append(hit)
        }
        if hits.isEmpty {
            return Found(hits: [], reach: .ok, note: empty)
        }
        return Found(hits: hits, reach: .ok, note: "")
    }

    private static func hit(from feature: [String: Any], allowed: PlaceNameClient.PlaceKind) -> PlaceNameClient.Hit? {
        let properties = feature["properties"] as? [String: Any] ?? [:]
        let coordinates = properties["coordinates"] as? [String: Any] ?? [:]
        let longitude = number(coordinates["longitude"])
        let latitude = number(coordinates["latitude"])
        let geometry = doubles((feature["geometry"] as? [String: Any])?["coordinates"])
        let lon = longitude ?? (geometry.count >= 2 ? geometry[0] : nil)
        let lat = latitude ?? (geometry.count >= 2 ? geometry[1] : nil)
        guard let lon, let lat else { return nil }
        let name = (properties["name"] as? String)
            ?? (properties["full_address"] as? String)
            ?? (properties["address"] as? String)
            ?? "이름 없는 장소"
        let id = (properties["mapbox_id"] as? String) ?? String(format: "%.5f,%.5f", lat, lon)
        let ids = properties["poi_category_ids"] as? [String] ?? []
        return PlaceNameClient.Hit(id: id, name: name, latitude: lat, longitude: lon, kind: kind(ids: ids, allowed: allowed))
    }

    /// 결과 종류가 식당 또는 숙소일 때만 그 말을 허용합니다. 검색이 그 종류가 아니면 붙이지 않습니다.
    private static func kind(ids: [String], allowed: PlaceNameClient.PlaceKind) -> PlaceNameClient.PlaceKind {
        switch allowed {
        case .restaurant:
            let restaurant = ids.contains("restaurant") || ids.contains { $0.hasSuffix("_restaurant") }
            return restaurant ? .restaurant : .plain
        case .lodging:
            return ids.contains("lodging") ? .lodging : .plain
        case .plain:
            return .plain
        }
    }

    private static func reason(for code: String) -> String {
        switch code {
        case "NoRoute":
            return "이 두 지점 사이 길이 없습니다."
        case "NoSegment":
            return "출발이나 도착 근처에 길이 없습니다."
        default:
            return "길을 가져오지 못했습니다."
        }
    }

    private static func same(_ left: PlaceNameClient.Hit, _ right: PlaceNameClient.Hit) -> Bool {
        left.name == right.name
            && abs(left.latitude - right.latitude) < 0.0002
            && abs(left.longitude - right.longitude) < 0.0002
    }

    private static func endpoint(_ base: String, _ items: [URLQueryItem]) -> URL? {
        var parts = URLComponents(string: base)
        parts?.queryItems = items
        return parts?.url
    }

    private static func json(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func doubles(_ value: Any?) -> [Double] {
        if let list = value as? [Double] { return list }
        if let list = value as? [NSNumber] { return list.map(\.doubleValue) }
        return []
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()
}
