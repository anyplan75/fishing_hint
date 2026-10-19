import Foundation

// 공개 지도에서 방파제, 낚시터, 백사장, 포구를 찾습니다.
// 사람이 숨겨 둔 비밀 포인트는 여기 없고, 내가 찍은 자리로 따로 저장합니다.

enum NearbyFinder {
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    static func search(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [FishingPoint] {
        let meters = Int(min(radiusKm, 30) * 1000)
        let query = """
        [out:json][timeout:20];
        (
          node(around:\(meters),\(latitude),\(longitude))["man_made"="pier"];
          way(around:\(meters),\(latitude),\(longitude))["man_made"="pier"];
          node(around:\(meters),\(latitude),\(longitude))["leisure"="fishing"];
          way(around:\(meters),\(latitude),\(longitude))["leisure"="fishing"];
          node(around:\(meters),\(latitude),\(longitude))["natural"="beach"];
          way(around:\(meters),\(latitude),\(longitude))["natural"="beach"];
          node(around:\(meters),\(latitude),\(longitude))["harbour"];
          way(around:\(meters),\(latitude),\(longitude))["harbour"];
        );
        out center 40;
        """
        var lastError: Error = URLError(.badServerResponse)
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            do {
                return try await once(url: url, query: query, latitude: latitude, longitude: longitude)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 질의 본문을 직접 만듭니다. 주소 없는 URLComponents 는 본문이 비어 주변 검색이 조용히 실패할 수 있습니다.
    private static func once(url: URL, query: String, latitude: Double, longitude: Double) async throws -> [FishingPoint] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("바로낚시/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let elements = object?["elements"] as? [[String: Any]] ?? []
        var points: [FishingPoint] = []
        var seen = Set<String>()
        for element in elements {
            guard let point = makePoint(element, originLat: latitude, originLon: longitude) else { continue }
            let key = "\(Int(point.latitude * 200)):\(Int(point.longitude * 200)):\(point.name)"
            if seen.insert(key).inserted { points.append(point) }
        }
        return points.sorted {
            Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude) < Geo.kilometers(latitude, longitude, $1.latitude, $1.longitude)
        }
    }

    private static func makePoint(_ element: [String: Any], originLat: Double, originLon: Double) -> FishingPoint? {
        let tags = element["tags"] as? [String: String] ?? [:]
        let lat = element["lat"] as? Double ?? (element["center"] as? [String: Any])?["lat"] as? Double
        let lon = element["lon"] as? Double ?? (element["center"] as? [String: Any])?["lon"] as? Double
        guard let lat, let lon else { return nil }
        let kind = placeKind(tags)
        let name = tags["name:ko"] ?? tags["name"] ?? "\(kind.title) \(FieldFormat.distance(Geo.kilometers(originLat, originLon, lat, lon)))"
        let type = element["type"] as? String ?? "node"
        let id = element["id"] as? NSNumber
        return FishingPoint(
            id: "osm-\(type)-\(id?.stringValue ?? UUID().uuidString)",
            name: name,
            latitude: lat,
            longitude: lon,
            place: kind,
            water: kind == .freshwater ? .fresh : .sea,
            source: "주변",
            bottom: "",
            targetMemo: "",
            measuredTempC: nil,
            memo: ""
        )
    }

    private static func placeKind(_ tags: [String: String]) -> PlaceKind {
        if tags["man_made"] == "pier" { return .pier }
        if tags["natural"] == "beach" || tags["leisure"] == "beach" { return .beach }
        if tags["harbour"] != nil { return .harbor }
        if tags["leisure"] == "fishing" { return .custom }
        return .pier
    }
}
