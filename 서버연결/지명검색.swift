import Foundation

// 지도에서 받은 지명으로 낚시 포인트를 찾습니다.
// 구글은 Custom Search를 쓰지 않습니다. 이미 있는 제미나이 암호로 Google Search grounding만 부릅니다.
// 인용 출처에 나온 지명만 남기고, 모델이 출처 없이 적은 이름은 버립니다.
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
        /// 구글이 검색 제안으로 준 HTML입니다. 약관상 결과와 함께 보여 줍니다. 없으면 빈 문자열입니다.
        var suggestHtml: String
    }

    private struct Page {
        var title: String
        var body: String
        var link: String
        var source: String
    }

    private struct Span {
        var text: String
        var link: String
    }

    private struct Ground {
        var spans: [Span]
        var html: String
        var model: String
        var connected: Bool
        var reason: String
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private static let landforms = ["방파제", "갯바위", "선착장", "포구", "해수욕장", "해변", "부두", "등대", "방조제", "낚시터"]
    private static let models = ["gemini-3.8-flash", "gemini-2.5-flash"]

    /// 기준점 지명과 주변 지명을 한 번 검색하고, 인용된 이름으로 상세를 한 번만 더 검색합니다.
    static func load(
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        mapboxToken: String,
        naverId: String,
        naverSecret: String,
        geminiKey: String
    ) async -> Load {
        let names = await placeNames(latitude: latitude, longitude: longitude, token: mapboxToken)
        let naverId = naverId.trimmingCharacters(in: .whitespacesAndNewlines)
        let naverSecret = naverSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let geminiKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameLine = names.isEmpty
            ? "지도에서 지명을 받지 못했습니다."
            : "지도 지명 \(names.joined(separator: ", "))로 검색합니다."
        var naverReason = ""
        var googleReason = ""
        if naverId.isEmpty || naverSecret.isEmpty {
            naverReason = "네이버 검색 없음. 비밀 파일에 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 이 필요합니다."
        }
        if geminiKey.isEmpty {
            googleReason = "구글 검색 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다."
        }
        guard !names.isEmpty else {
            return Load(points: [], note: [nameLine, naverReason, googleReason].filter { !$0.isEmpty }.joined(separator: " "), searchedNames: [], naverConnected: false, googleConnected: false, naverReason: naverReason, googleReason: googleReason, suggestHtml: "")
        }
        if !naverReason.isEmpty && !googleReason.isEmpty {
            let note = [nameLine, naverReason, googleReason].joined(separator: " ")
            return Load(points: [], note: note, searchedNames: names, naverConnected: false, googleConnected: false, naverReason: naverReason, googleReason: googleReason, suggestHtml: "")
        }

        var pages: [Page] = []
        var naverConnected = false
        if naverReason.isEmpty {
            for name in names {
                if Task.isCancelled { break }
                let query = name.contains("낚시") ? name : "\(name) 낚시"
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
            if !naverConnected && naverReason.isEmpty {
                naverReason = "네이버 검색 없음. 공식 검색을 읽지 못했습니다."
            }
        }

        var googleConnected = false
        var suggestHtml = ""
        var cited: [(name: String, link: String, corpus: String)] = []
        if googleReason.isEmpty {
            let asked = names.joined(separator: ", ")
            let first = await ground(
                prompt: """
                반드시 지금 구글 웹 검색을 실행하라. 검색을 건너뛰지 마라.
                오늘 웹 검색 결과에 실제로 나온 지명만 적어라. \(asked) 주변의 바다낚시 포인트다.
                검색 결과에 없는 이름은 적지 마라. 기억으로 보충하지 마라.
                수심, 위험, 새 포인트는 검색 결과에 있을 때만 적어라.
                """,
                apiKey: geminiKey,
                models: models
            )
            suggestHtml = first.html
            googleConnected = first.connected
            googleReason = first.reason
            cited = placeNames(in: first.spans)
            if googleConnected, !cited.isEmpty {
                let detail = await ground(
                    prompt: """
                    반드시 지금 구글 웹 검색을 실행하라. 검색을 건너뛰지 마라.
                    다음 낚시 포인트만 검색하라: \(cited.map(\.name).joined(separator: ", "))
                    검색 결과에 나온 어종, 지형, 주의만 짧게 적어라.
                    검색에 없는 수심, 위험, 새 지명은 만들지 마라.
                    """,
                    apiKey: geminiKey,
                    models: [first.model]
                )
                if suggestHtml.isEmpty { suggestHtml = detail.html }
                cited = mergeDetails(cited, detail: detail.spans)
            }
        }

        let keepKm = min(radiusKm, 18)
        var points = await pointsFrom(
            pages: pages,
            latitude: latitude,
            longitude: longitude,
            radiusKm: keepKm,
            token: mapboxToken,
            naverId: naverId,
            naverSecret: naverSecret,
            naverOpen: naverReason.isEmpty || naverConnected
        )
        let grounded = await pointsFromCited(
            cited,
            latitude: latitude,
            longitude: longitude,
            radiusKm: keepKm,
            token: mapboxToken
        )
        for point in grounded where !points.contains(where: { $0.name == point.name }) {
            points.append(point)
        }

        var bits = [nameLine]
        if points.isEmpty {
            bits.append("검색 글에서 기준점 \(Int(keepKm))km 안에 위치를 정한 포인트는 없습니다.")
        } else {
            bits.append("검색으로 기준점 \(Int(keepKm))km 안 \(points.count)곳을 넣었습니다.")
        }
        if !naverReason.isEmpty { bits.append(naverReason) }
        if !googleReason.isEmpty { bits.append(googleReason) }
        return Load(
            points: points,
            note: bits.joined(separator: " "),
            searchedNames: names,
            naverConnected: naverConnected,
            googleConnected: googleConnected,
            naverReason: naverReason,
            googleReason: googleReason,
            suggestHtml: suggestHtml
        )
    }

    /// 도구 흔적이 없는 모델은 다음 모델로 한 번만 넘깁니다. 출처 URL이 없는 문장은 이름으로 쓰지 않습니다.
    private static func ground(prompt: String, apiKey: String, models: [String]) async -> Ground {
        var last = Ground(spans: [], html: "", model: models.first ?? "", connected: false, reason: "구글 검색 없음. 검색 호출이 실패했습니다.")
        for model in models where !model.isEmpty {
            let result = await callGround(model: model, prompt: prompt, apiKey: apiKey)
            last = result
            if result.connected || result.reason.contains("거절") { return result }
            if !result.spans.isEmpty { return result }
        }
        return last
    }

    private static func callGround(model: String, prompt: String, apiKey: String) async -> Ground {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return Ground(spans: [], html: "", model: model, connected: false, reason: "구글 검색 없음. 검색 호출이 실패했습니다.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "tools": [["google_search": [String: String]()]],
            "toolConfig": ["includeServerSideToolInvocations": true],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return Ground(spans: [], html: "", model: model, connected: false, reason: "구글 검색 없음. 검색 호출이 실패했습니다.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return Ground(spans: [], html: "", model: model, connected: false, reason: "구글 검색 없음. 인증이 거절되었습니다.")
        }
        guard (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Ground(spans: [], html: "", model: model, connected: false, reason: "구글 검색 없음. 검색 호출이 실패했습니다.")
        }
        if object["error"] != nil {
            return Ground(spans: [], html: "", model: model, connected: false, reason: "구글 검색 없음. 인증이 거절되었습니다.")
        }
        let parsed = parseGround(object)
        if parsed.spans.isEmpty {
            let reason = parsed.sawTool
                ? "구글 검색 없음. 인용 출처가 오지 않았습니다."
                : "구글 검색 없음. 검색 도구 흔적이 없습니다."
            return Ground(spans: [], html: parsed.html, model: model, connected: false, reason: reason)
        }
        return Ground(spans: parsed.spans, html: parsed.html, model: model, connected: true, reason: "")
    }

    private static func parseGround(_ object: [String: Any]) -> (spans: [Span], html: String, sawTool: Bool) {
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        guard let candidate = candidates.first else { return ([], "", false) }
        let content = candidate["content"] as? [String: Any] ?? [:]
        let parts = content["parts"] as? [[String: Any]] ?? []
        let sawCall = parts.contains { $0["toolCall"] != nil }
        let meta = candidate["groundingMetadata"] as? [String: Any] ?? [:]
        let html = (meta["searchEntryPoint"] as? [String: Any])?["renderedContent"] as? String ?? ""
        let chunks = meta["groundingChunks"] as? [[String: Any]] ?? []
        var links: [String] = []
        for chunk in chunks {
            let web = chunk["web"] as? [String: Any] ?? [:]
            links.append((web["uri"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let supports = meta["groundingSupports"] as? [[String: Any]] ?? []
        var spans: [Span] = []
        for support in supports {
            let segment = support["segment"] as? [String: Any] ?? [:]
            let text = (segment["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let indices = support["groundingChunkIndices"] as? [Int] ?? []
            let link = indices.compactMap { index -> String? in
                guard links.indices.contains(index), !links[index].isEmpty else { return nil }
                return links[index]
            }.first ?? ""
            guard !text.isEmpty, !link.isEmpty else { continue }
            spans.append(Span(text: text, link: link))
        }
        return (spans, html, sawCall || links.contains { !$0.isEmpty })
    }

    /// 출처 URL이 붙은 문장에서만 지명을 뽑습니다. 그 문장 밖 이름은 넣지 않습니다.
    private static func placeNames(in spans: [Span]) -> [(name: String, link: String, corpus: String)] {
        var found: [(name: String, link: String, corpus: String)] = []
        for span in spans {
            var names = pointNames(in: span.text)
            if let whole = citedPlace(span.text), !names.contains(whole) { names.append(whole) }
            for name in names {
                if let index = found.firstIndex(where: { $0.name == name }) {
                    found[index].corpus += " " + span.text
                    continue
                }
                found.append((name, span.link, span.text))
                if found.count >= 8 { return found }
            }
        }
        return found
    }

    /// 상세 검색에서 그 지명이 적힌 인용 문장만 붙입니다. 지명이 없는 문장은 버립니다.
    private static func mergeDetails(
        _ cited: [(name: String, link: String, corpus: String)],
        detail: [Span]
    ) -> [(name: String, link: String, corpus: String)] {
        cited.map { item in
            let extra = detail.filter { $0.text.contains(item.name) }.map(\.text).joined(separator: " ")
            var copy = item
            if !extra.isEmpty { copy.corpus += " " + extra }
            return copy
        }
    }

    private static func citedPlace(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 24 else { return nil }
        let banned = ["검색", "결과", "구글", "반드시", "적어", "입니다", "포인트", "낚시", "주변", "오늘"]
        if banned.contains(where: { text.contains($0) }) { return nil }
        let hangul = text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        guard hangul >= 2 else { return nil }
        return text
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

    private static func pointsFrom(
        pages: [Page],
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        token: String,
        naverId: String,
        naverSecret: String,
        naverOpen: Bool
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
            if Task.isCancelled { break }
            var corpus = item.page.title + " " + item.page.body
            if naverOpen {
                let query = item.name.contains("낚시") ? item.name : "\(item.name) 낚시"
                if case .pages(let rows) = await naver(query: query, path: "webkr.json", id: naverId, secret: naverSecret) {
                    corpus += " " + rows.prefix(3).map { $0.title + " " + $0.body }.joined(separator: " ")
                }
            }
            if let point = await locatedPoint(name: item.name, corpus: corpus, link: item.page.link, source: item.page.source, latitude: latitude, longitude: longitude, radiusKm: radiusKm, token: token) {
                points.append(point)
            }
            if points.count >= 10 { break }
        }
        return points
    }

    private static func pointsFromCited(
        _ cited: [(name: String, link: String, corpus: String)],
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        token: String
    ) async -> [FishingPoint] {
        var points: [FishingPoint] = []
        for item in cited {
            if Task.isCancelled { break }
            guard let point = await locatedPoint(name: item.name, corpus: item.corpus, link: item.link, source: "구글", latitude: latitude, longitude: longitude, radiusKm: radiusKm, token: token) else { continue }
            if points.contains(where: { $0.name == point.name }) { continue }
            points.append(point)
            if points.count >= 10 { break }
        }
        return points
    }

    /// 검색에 없는 수심과 위험은 넣지 않습니다. 주의 문장은 인용 문장에 그 말이 있을 때만 붙입니다.
    private static func locatedPoint(
        name: String,
        corpus: String,
        link: String,
        source: String,
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        token: String
    ) async -> FishingPoint? {
        let looked = await PlaceNameClient.forward(query: name, latitude: latitude, longitude: longitude, token: token)
        guard let hit = looked.hits
            .map({ ($0, Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude)) })
            .filter({ $0.1 <= radiusKm + 0.4 })
            .min(by: { $0.1 < $1.1 })?.0 else { return nil }
        let species = TackleBook.speciesOrder.filter { corpus.contains($0) }
        let terrain = landforms.filter { corpus.contains($0) }
        let caution = cautionLine(in: corpus)
        var memoBits: [String] = []
        if !species.isEmpty { memoBits.append("어종 \(species.joined(separator: ", "))") }
        if !terrain.isEmpty { memoBits.append("지형 \(terrain.joined(separator: ", "))") }
        if !caution.isEmpty { memoBits.append("주의 \(caution)") }
        if !link.isEmpty { memoBits.append("출처 \(source) \(link)") }
        else { memoBits.append("출처 \(source)") }
        return FishingPoint(
            id: "web-\(stable(name, hit.latitude, hit.longitude))",
            name: name,
            latitude: hit.latitude,
            longitude: hit.longitude,
            place: kind(name: name, text: corpus),
            water: water(text: corpus, name: name),
            source: source,
            bottom: terrain.joined(separator: ", "),
            targetMemo: species.joined(separator: ", "),
            measuredTempC: nil,
            memo: memoBits.joined(separator: ". ")
        )
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
        let banned = ["낚시", "추천", "정보", "조황", "최고", "인기", "근처", "주변", "오늘", "블로그", "검색", "결과"]
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
