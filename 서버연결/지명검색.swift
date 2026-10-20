import Foundation

// 지도에서 받은 지명에 낚시를 붙여, 네이버와 구글의 공식 검색만 부릅니다.
// 로그인 뒤의 글과 비공개 글은 보지 않습니다. 막히면 다른 주소로 돌아가지 않습니다.
// 키 값은 이 파일에 없습니다.

enum PlaceWebSearch {
    struct Load {
        var points: [FishingPoint]
        var note: String
        var searchedNames: [String]
        var naverConnected: Bool
        var googleConnected: Bool
        var naverReason: String
        var googleReason: String
    }

    private struct Page {
        var title: String
        var body: String
        var link: String
        var source: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private static let landforms = ["방파제", "갯바위", "선착장", "포구", "해수욕장", "해변", "부두", "등대", "방조제", "낚시터"]

    /// 기준점 지명과 주변 지명을 지도에서 받은 뒤, 그 이름에 낚시를 붙여 공식 검색만 합니다.
    static func load(
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        mapboxToken: String,
        naverId: String,
        naverSecret: String,
        googleKey: String,
        googleEngine: String
    ) async -> Load {
        let names = await placeNames(latitude: latitude, longitude: longitude, token: mapboxToken)
        let naverId = naverId.trimmingCharacters(in: .whitespacesAndNewlines)
        let naverSecret = naverSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let googleKey = googleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let googleEngine = googleEngine.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameLine = names.isEmpty
            ? "지도에서 지명을 받지 못했습니다."
            : "지도 지명 \(names.joined(separator: ", "))에 낚시를 붙여 검색합니다."
        var naverReason = ""
        var googleReason = ""
        var naverConnected = false
        var googleConnected = false
        if naverId.isEmpty || naverSecret.isEmpty {
            naverReason = "네이버 검색 없음. 비밀 파일에 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 이 필요합니다."
        }
        if googleKey.isEmpty || googleEngine.isEmpty {
            googleReason = "구글 검색 없음. 비밀 파일에 GOOGLE_SEARCH_API_KEY, GOOGLE_SEARCH_ENGINE_ID 가 필요합니다."
        }
        guard !names.isEmpty else {
            return Load(points: [], note: [nameLine, naverReason, googleReason].filter { !$0.isEmpty }.joined(separator: " "), searchedNames: [], naverConnected: false, googleConnected: false, naverReason: naverReason, googleReason: googleReason)
        }
        if naverReason.isEmpty == false && googleReason.isEmpty == false {
            let note = [nameLine, naverReason, googleReason].joined(separator: " ")
            return Load(points: [], note: note, searchedNames: names, naverConnected: false, googleConnected: false, naverReason: naverReason, googleReason: googleReason)
        }
        var pages: [Page] = []
        for name in names {
            let query = name.contains("낚시") ? name : "\(name) 낚시"
            if naverReason.isEmpty {
                let web = await naver(query: query, path: "webkr.json", id: naverId, secret: naverSecret)
                let blog = await naver(query: query, path: "blog.json", id: naverId, secret: naverSecret)
                if case .rejected = web { naverReason = "네이버 검색 없음. 인증키가 이 자료를 거절했습니다."; naverConnected = false }
                if case .rejected = blog { naverReason = "네이버 검색 없음. 인증키가 이 자료를 거절했습니다."; naverConnected = false }
                if case .pages(let rows) = web { pages.append(contentsOf: rows); naverConnected = naverReason.isEmpty }
                if case .pages(let rows) = blog { pages.append(contentsOf: rows); naverConnected = naverReason.isEmpty }
                if case .failed = web, case .failed = blog, naverReason.isEmpty {
                    naverReason = "네이버 검색 없음. 공식 검색 호출이 실패했습니다."
                }
            }
            if googleReason.isEmpty {
                let found = await google(query: query, key: googleKey, engine: googleEngine)
                if case .rejected = found { googleReason = "구글 검색 없음. 인증키가 이 자료를 거절했습니다."; googleConnected = false }
                if case .pages(let rows) = found { pages.append(contentsOf: rows); googleConnected = googleReason.isEmpty }
                if case .failed = found, googleReason.isEmpty {
                    googleReason = "구글 검색 없음. 공식 검색 호출이 실패했습니다."
                }
            }
        }
        if !naverConnected && naverReason.isEmpty {
            naverReason = "네이버 검색 없음. 공식 검색을 읽지 못했습니다."
        }
        if !googleConnected && googleReason.isEmpty {
            googleReason = "구글 검색 없음. 공식 검색을 읽지 못했습니다."
        }
        let points = await pointsFrom(pages: pages, latitude: latitude, longitude: longitude, radiusKm: radiusKm, token: mapboxToken, naverId: naverId, naverSecret: naverSecret, googleKey: googleKey, googleEngine: googleEngine, naverOpen: naverReason.isEmpty || naverConnected, googleOpen: googleReason.isEmpty || googleConnected)
        var bits = [nameLine]
        if points.isEmpty {
            bits.append("검색 글에서 기준점 근처에 위치를 정한 포인트는 없습니다.")
        } else {
            bits.append("검색으로 기준점 근처 \(points.count)곳을 넣었습니다.")
        }
        if !naverReason.isEmpty { bits.append(naverReason) }
        if !googleReason.isEmpty { bits.append(googleReason) }
        return Load(points: points, note: bits.joined(separator: " "), searchedNames: names, naverConnected: naverConnected, googleConnected: googleConnected, naverReason: naverReason, googleReason: googleReason)
    }

    private static func placeNames(latitude: Double, longitude: Double, token: String) async -> [String] {
        var names: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let chunks = raw.replacingOccurrences(of: ",", with: " ")
                .split { $0.isWhitespace || $0 == "·" }
            for chunk in chunks {
                let text = String(chunk).trimmingCharacters(in: .punctuationCharacters)
                guard isPlaceName(text), !names.contains(text) else { continue }
                names.append(text)
                if names.count >= 6 { return }
            }
        }
        let labels = await PlaceNameClient.areaLabels(latitude: latitude, longitude: longitude, token: token)
        for label in labels { add(label) }
        let shifts = [(0.0, 0.0), (0.03, 0.0), (-0.03, 0.0), (0.0, 0.03), (0.0, -0.03)]
        for shift in shifts where names.count < 6 {
            let looked = await PlaceNameClient.reverse(latitude: latitude + shift.0, longitude: longitude + shift.1, token: token)
            add(looked.name)
        }
        return Array(names.prefix(6))
    }

    /// 나라 이름과 우편번호는 낚시 지명이 아니므로 검색어에서 빼 둡니다.
    private static func isPlaceName(_ text: String) -> Bool {
        guard text.count >= 2, text.count <= 12 else { return false }
        let banned = ["대한민국", "한국", "남한", "북한", "korea", "south", "republic"]
        if banned.contains(text.lowercased()) { return false }
        if text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return false }
        let hangul = text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        return hangul >= 2
    }

    private enum Fetch {
        case pages([Page])
        case rejected
        case failed
    }

    private static func naver(query: String, path: String, id: String, secret: String) async -> Fetch {
        var parts = URLComponents(string: "https://openapi.naver.com/v1/search/\(path)")
        parts?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: "10"),
            URLQueryItem(name: "start", value: "1"),
            URLQueryItem(name: "sort", value: "sim"),
        ]
        guard let url = parts?.url else { return .failed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.assumesHTTP3Capable = false
        request.setValue(id, forHTTPHeaderField: "X-Naver-Client-Id")
        request.setValue(secret, forHTTPHeaderField: "X-Naver-Client-Secret")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        if http.statusCode == 401 || http.statusCode == 403 { return .rejected }
        guard (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
        if object["errorCode"] != nil || object["errorMessage"] != nil { return .rejected }
        let items = object["items"] as? [[String: Any]] ?? []
        let pages = items.compactMap { item -> Page? in
            let title = plain(item["title"] as? String ?? "")
            let body = plain(item["description"] as? String ?? "")
            let link = item["link"] as? String ?? ""
            guard !title.isEmpty || !body.isEmpty else { return nil }
            return Page(title: title, body: body, link: link, source: "네이버")
        }
        return .pages(pages)
    }

    private static func google(query: String, key: String, engine: String) async -> Fetch {
        var parts = URLComponents(string: "https://www.googleapis.com/customsearch/v1")
        parts?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "cx", value: engine),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "5"),
            URLQueryItem(name: "hl", value: "ko"),
        ]
        guard let url = parts?.url else { return .failed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.assumesHTTP3Capable = false
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed }
        if http.statusCode == 401 || http.statusCode == 403 { return .rejected }
        guard (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
        if object["error"] != nil { return .rejected }
        let items = object["items"] as? [[String: Any]] ?? []
        let pages = items.compactMap { item -> Page? in
            let title = plain(item["title"] as? String ?? "")
            let body = plain(item["snippet"] as? String ?? "")
            let link = item["link"] as? String ?? ""
            guard !title.isEmpty || !body.isEmpty else { return nil }
            return Page(title: title, body: body, link: link, source: "구글")
        }
        return .pages(pages)
    }

    private static func pointsFrom(
        pages: [Page],
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        token: String,
        naverId: String,
        naverSecret: String,
        googleKey: String,
        googleEngine: String,
        naverOpen: Bool,
        googleOpen: Bool
    ) async -> [FishingPoint] {
        var named: [(name: String, page: Page)] = []
        for page in pages {
            let blob = page.title + " " + page.body
            for name in pointNames(in: blob) {
                if named.contains(where: { $0.name == name }) { continue }
                named.append((name, page))
                if named.count >= 6 { break }
            }
            if named.count >= 6 { break }
        }
        var points: [FishingPoint] = []
        for item in named {
            let detailPages = await detailPages(for: item.name, naverOpen: naverOpen, googleOpen: googleOpen, naverId: naverId, naverSecret: naverSecret, googleKey: googleKey, googleEngine: googleEngine)
            let corpus = ([item.page] + detailPages).map { $0.title + " " + $0.body }.joined(separator: " ")
            let looked = await PlaceNameClient.forward(query: item.name, latitude: latitude, longitude: longitude, token: token)
            guard let hit = looked.hits
                .map({ ($0, Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude)) })
                .filter({ $0.1 <= radiusKm + 0.4 })
                .min(by: { $0.1 < $1.1 })?.0 else { continue }
            let species = TackleBook.speciesOrder.filter { corpus.contains($0) }
            let terrain = landforms.filter { corpus.contains($0) }
            let caution = cautionLine(in: corpus)
            var memoBits: [String] = []
            if !species.isEmpty { memoBits.append("어종 \(species.joined(separator: ", "))") }
            if !terrain.isEmpty { memoBits.append("지형 \(terrain.joined(separator: ", "))") }
            if !caution.isEmpty { memoBits.append("주의 \(caution)") }
            let sourcePages = ([item.page] + detailPages).filter { $0.source == item.page.source || !$0.link.isEmpty }
            let sourceName = item.page.source
            if !item.page.link.isEmpty { memoBits.append("출처 \(sourceName) \(item.page.link)") }
            else { memoBits.append("출처 \(sourceName)") }
            let extra = sourcePages.first { $0.link != item.page.link && !$0.link.isEmpty }
            if let extra { memoBits.append("출처 \(extra.source) \(extra.link)") }
            let point = FishingPoint(
                id: "web-\(stable(item.name, hit.latitude, hit.longitude))",
                name: item.name,
                latitude: hit.latitude,
                longitude: hit.longitude,
                place: kind(name: item.name, text: corpus),
                water: water(text: corpus, name: item.name),
                source: sourceName,
                bottom: terrain.joined(separator: ", "),
                targetMemo: species.joined(separator: ", "),
                measuredTempC: nil,
                memo: memoBits.joined(separator: ". ")
            )
            if points.contains(where: { $0.name == point.name }) { continue }
            points.append(point)
            if points.count >= 10 { break }
        }
        return points
    }

    private static func detailPages(
        for name: String,
        naverOpen: Bool,
        googleOpen: Bool,
        naverId: String,
        naverSecret: String,
        googleKey: String,
        googleEngine: String
    ) async -> [Page] {
        let query = name.contains("낚시") ? name : "\(name) 낚시"
        var pages: [Page] = []
        if naverOpen {
            if case .pages(let rows) = await naver(query: query, path: "webkr.json", id: naverId, secret: naverSecret) {
                pages.append(contentsOf: rows.prefix(3))
            }
        }
        if googleOpen {
            if case .pages(let rows) = await google(query: query, key: googleKey, engine: googleEngine) {
                pages.append(contentsOf: rows.prefix(3))
            }
        }
        return pages
    }

    private static func pointNames(in text: String) -> [String] {
        var found: [String] = []
        for suffix in landforms {
            var rest = Substring(text)
            while let range = rest.range(of: suffix) {
                if let name = headName(rest[..<range.lowerBound], suffix: suffix), !found.contains(name) {
                    found.append(name)
                }
                rest = rest[range.upperBound...]
            }
        }
        return found
    }

    private static func headName(_ before: Substring, suffix: String) -> String? {
        var chars: [Character] = []
        for ch in before.reversed() {
            if " \n\t,.\u{00B7}()[]/|:!?\"'<>".contains(ch) { break }
            chars.append(ch)
            if chars.count >= 10 { break }
        }
        let token = String(chars.reversed())
        guard token.count >= 1 else { return nil }
        let hangul = token.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        guard hangul >= 1 else { return nil }
        let banned = ["낚시", "추천", "정보", "조황", "최고", "인기", "근처", "주변", "오늘", "블로그"]
        if banned.contains(where: { token.contains($0) }) { return nil }
        let name = token + suffix
        guard name.count <= 18 else { return nil }
        return name
    }

    private static func cautionLine(in text: String) -> String {
        let marks = ["주의", "금지", "위험", "미끄", "통제", "입출", "금어"]
        guard let mark = marks.first(where: { text.contains($0) }),
              let range = text.range(of: mark) else { return "" }
        let start = text.index(range.lowerBound, offsetBy: -12, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 18, limitedBy: text.endIndex) ?? text.endIndex
        let clip = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clip)
    }

    private static func kind(name: String, text: String) -> PlaceKind {
        let blob = name + text
        if blob.contains("갯바위") { return .rock }
        if blob.contains("해변") || blob.contains("해수욕장") { return .beach }
        if blob.contains("포구") || blob.contains("선착장") || blob.contains("부두") || blob.contains("등대") || blob.contains("방조제") { return .harbor }
        if blob.contains("방파제") { return .pier }
        if blob.contains("저수지") || blob.contains("민물") { return .freshwater }
        return .custom
    }

    private static func water(text: String, name: String) -> WaterKind {
        let blob = name + text
        if blob.contains("저수지") || blob.contains("민물") || blob.contains("붕어") || blob.contains("배스") { return .fresh }
        if blob.contains("바다") || blob.contains("갯바위") || blob.contains("방파제") || blob.contains("포구") || blob.contains("해변") { return .sea }
        return .unknown
    }

    private static func plain(_ raw: String) -> String {
        var text = raw
        let swaps = ["&quot;": "\"", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&#39;": "'", "&nbsp;": " "]
        for (from, to) in swaps { text = text.replacingOccurrences(of: from, with: to) }
        while let open = text.range(of: "<"), let close = text.range(of: ">", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stable(_ name: String, _ latitude: Double, _ longitude: Double) -> String {
        let raw = "\(name)|\(String(format: "%.3f", latitude))|\(String(format: "%.3f", longitude))"
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }
}
