import Foundation

// 낚시 계획·바로가자에 붙이는 공식 자료와, 해루질 수중이 보는 스킨스쿠버지수입니다.
// 주소는 공공데이터포털 문서에 있는 것만 씁니다. 없는 자리는 만들지 않습니다.

struct OfficialIndexRow {
    var day: String
    var half: String
    var species: String
    var line: String
    var rank: Int
}

enum OfficialNotes {
    static var rows: [String: [OfficialIndexRow]] = [:]
    /// 바다낚시지수 키가 거절되면 자리마다 이 문장만 붙입니다. 여건을 만들지 않습니다.
    static var blocked: String?

    static func reset() {
        rows = [:]
        blocked = nil
    }

    static func sentence(pointId: String, species: String, when: Date) -> String? {
        if let blocked, rows[pointId] == nil {
            return blocked
        }
        guard let list = rows[pointId], !list.isEmpty else { return blocked }
        let calendar = Calendar(identifier: .gregorian)
        let hour = calendar.component(.hour, from: when)
        let half = hour < 12 ? "오전" : "오후"
        let day = dayText(when)
        let sameDay = list.filter { $0.day.isEmpty || $0.day == day }
        let pool = sameDay.isEmpty ? list : sameDay
        let sameHalf = pool.filter { $0.half.isEmpty || $0.half == half }
        let use = sameHalf.isEmpty ? pool : sameHalf
        if let named = use.first(where: { speciesMatch($0.species, species) }) {
            return named.line
        }
        return use.max { $0.rank < $1.rank }?.line
    }

    /// 카드에 성공률과 같이 보여 주는 짧은 지수 문장입니다. 없는 지수는 만들지 않습니다.
    static func caption(pointId: String, species: String, when: Date) -> String {
        let line = sentence(pointId: pointId, species: species, when: when) ?? "바다낚시지수 없음"
        if line.contains("거절") {
            return "바다낚시지수 없음. 인증키가 이 자료를 거절했습니다."
        }
        if line == "바다낚시지수 없음" || line == "지수 없음" || line.contains("없습니다") || line.contains("지어 넣지") {
            return "지수 없음"
        }
        return line
    }

    private static func speciesMatch(_ indexSpecies: String, _ picked: String) -> Bool {
        let name = indexSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "-" else { return false }
        return picked.contains(name) || name.contains(picked)
    }

    private static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum SeaFishingIndexClient {
    struct Load {
        var points: [FishingPoint]
        var note: String
        var connected: Bool
    }

    /// 활용가이드의 오퍼레이션만 부릅니다. 서비스 주소는 fcstFishingv2 입니다.
    static func load(latitude: Double, longitude: Double, radiusKm: Double, apiKey: String) async -> Load {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return Load(points: [], note: "바다낚시지수 없음. 비밀 파일에 DATA_GO_KR_FISHING_INDEX_KEY 가 없습니다.", connected: false)
        }
        let day = requestDay()
        switch await pages(apiKey: key, day: day) {
        case .rejected(let reason):
            return Load(points: [], note: reason, connected: false)
        case .failed(let reason):
            return Load(points: [], note: reason, connected: false)
        case .rows(let rows):
            let grouped = group(rows, latitude: latitude, longitude: longitude, radiusKm: radiusKm)
            if grouped.isEmpty {
                return Load(
                    points: [],
                    note: "바다낚시지수 연결됨. 기준점 반경 안에는 갯바위 지점이 없습니다.",
                    connected: true
                )
            }
            return Load(
                points: grouped,
                note: "바다낚시지수 갯바위 \(grouped.count)곳을 반경 안에서 읽었습니다.",
                connected: true
            )
        }
    }

    private enum PageResult {
        case rows([Item])
        case rejected(String)
        case failed(String)
    }

    private struct Item {
        var name: String
        var latitude: Double
        var longitude: Double
        var row: OfficialIndexRow
    }

    private static func pages(apiKey: String, day: String) async -> PageResult {
        var all: [Item] = []
        var page = 1
        var total = Int.max
        while page <= 8 && all.count < total {
            switch await onePage(apiKey: apiKey, day: day, page: page) {
            case .rejected(let reason):
                return .rejected(reason)
            case .failed(let reason):
                if all.isEmpty { return .failed(reason) }
                return .rows(all)
            case .rows(let chunk, let reported):
                if chunk.isEmpty { return .rows(all) }
                all.append(contentsOf: chunk)
                if let reported { total = reported }
                page += 1
            }
        }
        return .rows(all)
    }

    private enum OnePage {
        case rows([Item], Int?)
        case rejected(String)
        case failed(String)
    }

    private static func onePage(apiKey: String, day: String, page: Int) async -> OnePage {
        var last: OnePage = .failed("바다낚시지수 없음. 조회에 실패했습니다.")
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            last = await oneAttempt(apiKey: apiKey, day: day, page: page)
            switch last {
            case .rows, .rejected:
                return last
            case .failed:
                continue
            }
        }
        return last
    }

    /// 예전에 붙은 HTTP/3 기록을 쓰지 않습니다. 그 길로 가면 이 자료가 멈춥니다.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    private static func oneAttempt(apiKey: String, day: String, page: Int) async -> OnePage {
        guard let url = endpoint(apiKey: apiKey, day: day, page: page) else {
            return .failed("바다낚시지수 없음. 조회 주소를 만들지 못했습니다.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failed("바다낚시지수 없음. 조회에 실패했습니다.")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            if let reason = rejection(in: data) { return .rejected(reason) }
            return .failed("바다낚시지수 없음. 조회에 실패했습니다.")
        }
        if let reason = rejection(in: object) { return .rejected(reason) }
        if !(200..<300).contains(http.statusCode) {
            return .failed("바다낚시지수 없음. 조회에 실패했습니다.")
        }
        let code = headerValue(object, key: "resultCode")
        if code != "00" && code != "0" {
            let message = headerValue(object, key: "resultMsg")
            if message.contains("REGISTERED") || message.contains("DENIED") || message.contains("거절") {
                return .rejected("바다낚시지수 없음. 인증키가 이 자료를 거절했습니다.")
            }
            return .failed("바다낚시지수 없음. 조회에 실패했습니다.")
        }
        var items: [Item] = []
        collect(object, into: &items)
        let total = headerNumber(object, key: "totalCount")
        return .rows(items, total)
    }

    /// 활용가이드에 적힌 서비스 주소와 오퍼레이션입니다.
    private static func endpoint(apiKey: String, day: String, page: Int) -> URL? {
        let base = "https://apis.data.go.kr/1192136/fcstFishingv2/GetFcstFishingApiServicev2"
        let pairs = [
            ("serviceKey", apiKey),
            ("type", "json"),
            ("gubun", "갯바위"),
            ("reqDate", day),
            ("pageNo", "\(page)"),
            ("numOfRows", "300"),
        ]
        let query = pairs.map { key, value in
            "\(percent(key))=\(percent(value))"
        }.joined(separator: "&")
        return URL(string: base + "?" + query)
    }

    static func percent(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private static func rejection(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if text.contains("SERVICE_KEY_IS_NOT_REGISTERED_ERROR")
            || text.contains("등록되지 않은 서비스키")
            || text.contains("SERVICE_ACCESS_DENIED_ERROR")
            || text.contains("PERMISSION_DENIED") {
            return "바다낚시지수 없음. 인증키가 이 자료를 거절했습니다."
        }
        return nil
    }

    private static func rejection(in object: Any) -> String? {
        let message = headerValue(object, key: "errMsg") + headerValue(object, key: "returnAuthMsg")
        if message.contains("NOT_REGISTERED") || message.contains("DENIED") || message.contains("등록되지 않은") {
            return "바다낚시지수 없음. 인증키가 이 자료를 거절했습니다."
        }
        return nil
    }

    private static func headerValue(_ object: Any, key: String) -> String {
        if let dict = object as? [String: Any] {
            if let text = dict[key] as? String { return text }
            for child in dict.values {
                let found = headerValue(child, key: key)
                if !found.isEmpty { return found }
            }
        } else if let list = object as? [Any] {
            for child in list {
                let found = headerValue(child, key: key)
                if !found.isEmpty { return found }
            }
        }
        return ""
    }

    private static func headerNumber(_ object: Any, key: String) -> Int? {
        if let dict = object as? [String: Any] {
            if let number = dict[key] as? NSNumber { return number.intValue }
            if let text = dict[key] as? String, let number = Int(text) { return number }
            for child in dict.values {
                if let found = headerNumber(child, key: key) { return found }
            }
        }
        return nil
    }

    private static func collect(_ object: Any, into items: inout [Item]) {
        if let dict = object as? [String: Any] {
            if dict["seafsPstnNm"] != nil || (dict["lat"] != nil && dict["lot"] != nil && dict["totalIndex"] != nil) {
                if let item = item(dict) { items.append(item) }
                return
            }
            for child in dict.values { collect(child, into: &items) }
        } else if let list = object as? [Any] {
            for child in list { collect(child, into: &items) }
        }
    }

    private static func item(_ dict: [String: Any]) -> Item? {
        let name = text(dict["seafsPstnNm"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude = number(dict["lat"]), let longitude = number(dict["lot"]) else { return nil }
        guard !name.isEmpty, name != "-" else { return nil }
        let species = text(dict["seafsTgfshNm"])
        let half = text(dict["predcNoonSeCd"])
        let tide = text(dict["tdlvHrCn"])
        let wave = span("파고", dict["minWvhgt"], dict["maxWvhgt"], unit: "m")
        let water = span("수온", dict["minWtem"], dict["maxWtem"], unit: "도")
        let current = span("유속", dict["minCrsp"], dict["maxCrsp"], unit: "")
        let index = text(dict["totalIndex"])
        var bits = ["바다낚시지수 \(name)"]
        if !half.isEmpty { bits.append(half) }
        if !species.isEmpty, species != "-" { bits.append(species) }
        if !index.isEmpty { bits.append("지수 \(index)") }
        if !tide.isEmpty { bits.append("물때 \(tide)") }
        if !wave.isEmpty { bits.append(wave) }
        if !water.isEmpty { bits.append(water) }
        if !current.isEmpty { bits.append(current) }
        let row = OfficialIndexRow(
            day: dayKey(text(dict["predcYmd"])),
            half: half,
            species: species,
            line: bits.joined(separator: " "),
            rank: indexRank(index)
        )
        return Item(name: name, latitude: latitude, longitude: longitude, row: row)
    }

    private static func group(_ items: [Item], latitude: Double, longitude: Double, radiusKm: Double) -> [FishingPoint] {
        var buckets: [String: (FishingPoint, [OfficialIndexRow])] = [:]
        for item in items {
            let away = Geo.kilometers(latitude, longitude, item.latitude, item.longitude)
            guard away <= radiusKm + 0.4 else { continue }
            let key = "\(item.name)|\(String(format: "%.3f", item.latitude))|\(String(format: "%.3f", item.longitude))"
            if buckets[key] == nil {
                let point = FishingPoint(
                    id: "seaidx-\(stable(item.name, item.latitude, item.longitude))",
                    name: item.name,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    place: .rock,
                    water: .sea,
                    source: "바다낚시지수",
                    bottom: "",
                    targetMemo: "",
                    measuredTempC: nil,
                    memo: "해양수산부 국립해양조사원 바다낚시지수 갯바위 지점."
                )
                buckets[key] = (point, [])
            }
            buckets[key]?.1.append(item.row)
        }
        var points: [FishingPoint] = []
        for (_, pair) in buckets {
            OfficialNotes.rows[pair.0.id] = pair.1
            points.append(pair.0)
        }
        return points
    }

    static func attach(to points: [FishingPoint], anchors: [FishingPoint]) {
        for point in points where OfficialNotes.rows[point.id] == nil {
            let near = anchors
                .map { ($0, Geo.kilometers(point.latitude, point.longitude, $0.latitude, $0.longitude)) }
                .filter { $0.1 <= 15 }
                .min { $0.1 < $1.1 }
            guard let near, let copied = OfficialNotes.rows[near.0.id] else {
                OfficialNotes.rows[point.id] = [
                    OfficialIndexRow(day: "", half: "", species: "", line: "지수 없음", rank: 0),
                ]
                continue
            }
            let km = String(format: "%.1f", near.1)
            OfficialNotes.rows[point.id] = copied.map { row in
                var copy = row
                copy.line = "가까운 바다낚시지수 \(near.0.name)까지 \(km)km. " + row.line
                return copy
            }
        }
    }

    private static func span(_ title: String, _ low: Any?, _ high: Any?, unit: String) -> String {
        guard let low = number(low) ?? number(high as Any?) else { return "" }
        let highNumber = number(high) ?? low
        let left = format(low)
        let right = format(highNumber)
        if left == right { return "\(title) \(left)\(unit)" }
        return "\(title) \(left)–\(right)\(unit)"
    }

    private static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    static func indexRank(_ text: String) -> Int {
        if text.contains("매우좋") { return 5 }
        if text.contains("좋") { return 4 }
        if text.contains("보통") { return 3 }
        if text.contains("매우나") { return 1 }
        if text.contains("나쁨") { return 2 }
        return 0
    }

    private static func text(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func dayKey(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 8 else { return raw }
        let head = digits.prefix(8)
        let year = head.prefix(4)
        let month = head.dropFirst(4).prefix(2)
        let day = head.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    private static func requestDay() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    static func stable(_ name: String, _ latitude: Double, _ longitude: Double) -> String {
        let raw = "\(name)|\(String(format: "%.4f", latitude))|\(String(format: "%.4f", longitude))"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

enum FishingSpotStandardClient {
    struct Load {
        var points: [FishingPoint]
        var note: String
        var connected: Bool
    }

    /// 전국낚시터정보표준데이터 안내 페이지의 전국 파일 받기 주소입니다.
    static func load(latitude: Double, longitude: Double, radiusKm: Double) async -> Load {
        guard let url = URL(string: "https://file.localdata.go.kr/file/download/fishing_spot_info/info") else {
            return Load(points: [], note: "전국낚시터 없음. 표준데이터 주소를 만들지 못했습니다.", connected: false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        request.setValue("https://file.localdata.go.kr/file/fishing_spot_info/info", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return Load(points: [], note: "전국낚시터 없음. 표준데이터 파일을 가져오지 못했습니다.", connected: false)
        }
        guard let table = table(from: data), table.count > 1 else {
            return Load(points: [], note: "전국낚시터 없음. 표준데이터 파일을 읽지 못했습니다.", connected: false)
        }
        let header = table[0]
        guard let nameAt = header.firstIndex(of: "낚시터명"),
              let latAt = header.firstIndex(of: "WGS84위도"),
              let lonAt = header.firstIndex(of: "WGS84경도") else {
            return Load(points: [], note: "전국낚시터 없음. 표준데이터에 이름이나 좌표 칸이 없습니다.", connected: false)
        }
        func column(_ title: String) -> Int? { header.firstIndex(of: title) }
        let typeAt = column("낚시터유형")
        let speciesAt = column("주요어종")
        let feeAt = column("이용요금")
        let facilityAt = column("수상시설물유형")
        let pointAt = column("주요포인트")
        let idAt = column("관리번호")
        var points: [FishingPoint] = []
        var seen = Set<String>()
        for row in table.dropFirst() {
            guard nameAt < row.count, latAt < row.count, lonAt < row.count else { continue }
            let name = row[nameAt].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let spotLat = Double(row[latAt]), let spotLon = Double(row[lonAt]), spotLat != 0, spotLon != 0 else { continue }
            guard !name.isEmpty else { continue }
            let away = Geo.kilometers(latitude, longitude, spotLat, spotLon)
            guard away <= radiusKm + 0.4 else { continue }
            let type = cell(row, typeAt)
            let species = cell(row, speciesAt)
            let fee = cell(row, feeAt)
            let facility = cell(row, facilityAt)
            let mainPoint = cell(row, pointAt)
            let boat = [name, facility, mainPoint].joined(separator: " ").contains("선상")
                || [name, facility, mainPoint].joined(separator: " ").contains("낚시배")
            let paid = isPaid(fee) || name.contains("유료")
            guard paid || boat else { continue }
            let key = cell(row, idAt).isEmpty ? "\(name)|\(spotLat)|\(spotLon)" : cell(row, idAt)
            guard seen.insert(key).inserted else { continue }
            var memo = "전국낚시터정보표준데이터. 유형 \(type.isEmpty ? "자료에 없음" : type)."
            if !species.isEmpty { memo += " 주요어종 \(species)." }
            if !fee.isEmpty { memo += " 이용요금 \(fee)." }
            if boat { memo += " 자료에 선상 또는 낚시배가 적혀 있습니다." }
            points.append(FishingPoint(
                id: "std-\(SeaFishingIndexClient.stable(key, spotLat, spotLon))",
                name: name,
                latitude: spotLat,
                longitude: spotLon,
                place: boat ? .boat : placeKind(type),
                water: placeKind(type) == .freshwater ? .fresh : .sea,
                source: "낚시터표준",
                bottom: "",
                targetMemo: species,
                measuredTempC: nil,
                memo: memo
            ))
        }
        if points.isEmpty {
            return Load(points: [], note: "전국낚시터 연결됨. 기준점 반경 안에는 유료 낚시터나 선상 시설이 없습니다.", connected: true)
        }
        return Load(points: points, note: "전국낚시터 유료·선상 \(points.count)곳을 반경 안에서 읽었습니다.", connected: true)
    }

    private static func isPaid(_ fee: String) -> Bool {
        let text = fee.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text != "0" && text != "-" && text != "없음" && text != "무료"
    }

    private static func placeKind(_ type: String) -> PlaceKind {
        if type == "저수지" || type == "계곡" || type == "평지" { return .freshwater }
        if type == "바다" { return .rock }
        return .custom
    }

    private static func cell(_ row: [String], _ index: Int?) -> String {
        guard let index, index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func table(from data: Data) -> [[String]]? {
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0422))
        let text = String(data: data, encoding: cp949) ?? String(data: data, encoding: .utf8)
        guard let text, text.contains("낚시터명") else { return nil }
        return parseCSV(text)
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    quoted = false
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                quoted = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char == "\n" {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else if char != "\r" {
                field.append(char)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

enum SkinScubaClient {
    struct Hour {
        var half: String
        var line: String
        var rank: Int
    }

    struct Place {
        var point: FishingPoint
        var hours: [Hour]
    }

    struct Load {
        var places: [Place]
        var note: String
        var connected: Bool
    }

    /// 예전에 붙은 HTTP/3 기록을 쓰지 않습니다. 거절 응답이 시간 초과로 가려지지 않게 합니다.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    /// 활용가이드에 있는 스킨스쿠버지수 오퍼레이션입니다. 기존 공공데이터 키만 씁니다.
    static func load(latitude: Double, longitude: Double, radiusKm: Double, apiKey: String, night: Bool) async -> Load {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return Load(places: [], note: "스킨스쿠버지수 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.", connected: false)
        }
        let hour = night ? "21" : "10"
        guard let url = endpoint(apiKey: key, stamp: requestStamp(hour: hour)) else {
            return Load(places: [], note: "스킨스쿠버지수 없음. 조회 주소를 만들지 못했습니다.", connected: false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return Load(places: [], note: "스킨스쿠버지수 없음. 조회에 실패했습니다.", connected: false)
        }
        if let text = String(data: data, encoding: .utf8),
           text.contains("SERVICE_KEY_IS_NOT_REGISTERED_ERROR")
            || text.contains("등록되지 않은 서비스키")
            || text.contains("SERVICE_ACCESS_DENIED_ERROR")
            || text.contains("PERMISSION_DENIED") {
            return Load(places: [], note: "스킨스쿠버지수 없음. 인증키가 이 자료를 거절했습니다.", connected: false)
        }
        guard (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return Load(places: [], note: "스킨스쿠버지수 없음. 조회에 실패했습니다.", connected: false)
        }
        var raw: [[String: Any]] = []
        collect(object, into: &raw)
        var buckets: [String: Place] = [:]
        for dict in raw {
            let name = text(dict["skscExpcnRgnNm"])
            guard let spotLat = number(dict["lat"]), let spotLon = number(dict["lot"]), !name.isEmpty, name != "-" else { continue }
            guard Geo.kilometers(latitude, longitude, spotLat, spotLon) <= radiusKm + 0.4 else { continue }
            let half = text(dict["predcNoonSeCd"])
            let tide = text(dict["tdlvHrCn"])
            let wave = span("파고", dict["minWvhgt"], dict["maxWvhgt"], "m")
            let water = span("수온", dict["minWtem"], dict["maxWtem"], "도")
            let current = span("유속", dict["minCrsp"], dict["maxCrsp"], "")
            let index = text(dict["totalIndex"])
            var bits = ["스킨스쿠버지수 \(name)"]
            if !half.isEmpty { bits.append(half) }
            if !index.isEmpty { bits.append("지수 \(index)") }
            if !tide.isEmpty { bits.append("물때 \(tide)") }
            if !wave.isEmpty { bits.append(wave) }
            if !water.isEmpty { bits.append(water) }
            if !current.isEmpty { bits.append(current) }
            let hourRow = Hour(half: half, line: bits.joined(separator: " "), rank: SeaFishingIndexClient.indexRank(index))
            let key = "\(name)|\(String(format: "%.3f", spotLat))|\(String(format: "%.3f", spotLon))"
            if buckets[key] == nil {
                let point = FishingPoint(
                    id: "scuba-\(SeaFishingIndexClient.stable(name, spotLat, spotLon))",
                    name: name,
                    latitude: spotLat,
                    longitude: spotLon,
                    place: .rock,
                    water: .sea,
                    source: "스킨스쿠버",
                    bottom: "",
                    targetMemo: "",
                    measuredTempC: nil,
                    memo: "해양수산부 국립해양조사원 스킨스쿠버지수 포인트."
                )
                buckets[key] = Place(point: point, hours: [])
            }
            buckets[key]?.hours.append(hourRow)
        }
        let places = Array(buckets.values)
        if places.isEmpty {
            return Load(places: [], note: "스킨스쿠버지수 연결됨. 기준점 반경 안에는 포인트가 없습니다.", connected: true)
        }
        return Load(places: places, note: "스킨스쿠버지수 포인트 \(places.count)곳을 반경 안에서 읽었습니다.", connected: true)
    }

    private static func endpoint(apiKey: String, stamp: String) -> URL? {
        let base = "https://apis.data.go.kr/1192136/fcstSkinScubav2/GetFcstSkinScubaApiServicev2"
        let pairs = [
            ("serviceKey", apiKey),
            ("type", "json"),
            ("reqDate", stamp),
            ("pageNo", "1"),
            ("numOfRows", "300"),
        ]
        let query = pairs.map { key, value in
            "\(SeaFishingIndexClient.percent(key))=\(SeaFishingIndexClient.percent(value))"
        }.joined(separator: "&")
        return URL(string: base + "?" + query)
    }

    private static func collect(_ object: Any, into items: inout [[String: Any]]) {
        if let dict = object as? [String: Any] {
            if dict["skscExpcnRgnNm"] != nil || (dict["lat"] != nil && dict["totalIndex"] != nil && dict["seafsPstnNm"] == nil) {
                items.append(dict)
                return
            }
            for child in dict.values { collect(child, into: &items) }
        } else if let list = object as? [Any] {
            for child in list { collect(child, into: &items) }
        }
    }

    private static func span(_ title: String, _ low: Any?, _ high: Any?, _ unit: String) -> String {
        guard let low = number(low) ?? number(high as Any?) else { return "" }
        let highNumber = number(high) ?? low
        if abs(low - highNumber) < 0.05 { return "\(title) \(trim(low))\(unit)" }
        return "\(title) \(trim(low))–\(trim(highNumber))\(unit)"
    }

    private static func trim(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    private static func text(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func requestStamp(hour: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date()) + hour
    }
}
