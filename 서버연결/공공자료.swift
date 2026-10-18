import Foundation

// 공개된 어장 파일과, 인증키가 있을 때의 조석예보만 다룹니다.
// 해로드 앱과 안전해 앱은 호출하지 않습니다.

struct TideSample {
    var time: Date
    var heightCm: Double
}

struct TideReport {
    var stationName: String
    var stationCode: String
    var distanceKm: Double
    var samples: [TideSample]
    /// 이 예보지점 조석을 자리의 간조 시각으로 써도 되는 거리인지입니다.
    var usable: Bool
    var note: String
}

enum TideReading {
    /// 양쪽보다 낮은 시각을 간조로 읽습니다. 자료에 없으면 빈 목록입니다.
    static func lowTimes(_ samples: [TideSample]) -> [Date] {
        let ordered = samples.sorted { $0.time < $1.time }
        guard ordered.count >= 3 else { return [] }
        var lows: [Date] = []
        for index in 1..<(ordered.count - 1) {
            let previous = ordered[index - 1].heightCm
            let current = ordered[index].heightCm
            let next = ordered[index + 1].heightCm
            if current <= previous, current <= next, (previous - current >= 3 || next - current >= 3) {
                lows.append(ordered[index].time)
            }
        }
        return lows
    }
}

enum PublicGroundNote {
    /// 좌표가 공개 어장 범위 안이면 경고 문장을 만들고, 아니면 확인된 자료가 없다고 적습니다.
    static func make(latitude: Double, longitude: Double) -> (summary: String, warnings: [String]) {
        let closed = "금어기·포획금지는 이 자리에서 확인된 공공자료가 없습니다. 관할 관청 고시를 따로 확인하세요."
        let hits = LicensedGroundBook.matches(latitude: latitude, longitude: longitude)
        if hits.isEmpty {
            return (
                "이 자리는 확인된 공공자료가 없음",
                [
                    "받아 둔 해양수산부 어장정보 2023 파일의 좌표 범위 밖입니다. 이 파일에 없다고 출입이 자유로운 것은 아닙니다.",
                    closed,
                ]
            )
        }
        var lines: [String] = []
        for hit in hits.prefix(3) {
            let village = hit.licenseName.contains("마을")
            let head = village
                ? "마을어장으로 표시된 좌표 범위 안입니다."
                : "면허 어장(\(hit.licenseName)) 좌표 범위 안입니다."
            let species = hit.species.isEmpty
                ? "자료에 대상 생물이 비어 있습니다."
                : "자료에 적힌 대상은 \(hit.species)입니다."
            let place = hit.placeText.isEmpty ? "" : " 위치 설명은 \(hit.placeText)입니다."
            let method = hit.method.isEmpty ? "" : " 어업 방법은 \(hit.method)입니다."
            let license = hit.licenseNo.isEmpty ? "" : " 면허번호는 \(hit.licenseNo)입니다."
            let period = " 자료상 면허 기간은 \(hit.startText)부터 \(hit.endText)까지입니다. 지금 유효한지는 이 파일만으로 확인하지 못했습니다."
            lines.append(head + " " + species + place + method + license + period + " 허가 없이 들어가거나 잡지 마세요.")
        }
        if hits.count > 3 {
            lines.append("같은 범위에 기록이 \(hits.count)건 있습니다. 위 3건만 적었습니다.")
        }
        lines.append(closed)
        let summary = hits.contains { $0.licenseName.contains("마을") }
            ? "마을어장 좌표 범위 안"
            : "면허 어장 좌표 범위 안"
        return (summary, lines)
    }
}

enum PublicTideClient {
    /// 인증키가 있고 가까운 조위관측소가 있을 때만 조석예보를 부릅니다.
    static func forecast(latitude: Double, longitude: Double, from: Date, to: Date, apiKey: String) async -> TideReport {
        guard let nearest = TideStationBook.nearest(latitude: latitude, longitude: longitude) else {
            return TideReport(stationName: "", stationCode: "", distanceKm: 0, samples: [], usable: false, note: "조위관측소 목록이 비어 있습니다. 들물·날물은 바다 예보 모델입니다.")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let distanceText = String(format: "%.0f", nearest.distanceKm)
        if key.isEmpty {
            return TideReport(
                stationName: nearest.station.name,
                stationCode: nearest.station.code,
                distanceKm: nearest.distanceKm,
                samples: [],
                usable: false,
                note: "국립해양조사원 조석예보는 공공데이터 인증키가 없어 붙이지 못했습니다. 들물·날물은 바다 예보 모델입니다."
            )
        }
        if nearest.distanceKm > 80 {
            return TideReport(
                stationName: nearest.station.name,
                stationCode: nearest.station.code,
                distanceKm: nearest.distanceKm,
                samples: [],
                usable: false,
                note: "가장 가까운 조석 예보지점 \(nearest.station.name)이 \(distanceText)km라 호출하지 않았습니다. 들물·날물은 바다 예보 모델입니다."
            )
        }
        var samples = await load(station: nearest.station, from: from, to: to, apiKey: key)
        var seen = Set<TimeInterval>()
        samples = samples.filter { seen.insert($0.time.timeIntervalSince1970).inserted }
        samples.sort { $0.time < $1.time }
        if samples.isEmpty {
            return TideReport(
                stationName: nearest.station.name,
                stationCode: nearest.station.code,
                distanceKm: nearest.distanceKm,
                samples: [],
                usable: false,
                note: "\(nearest.station.name) 조석예보를 가져오지 못했습니다. 들물·날물은 바다 예보 모델만 봅니다."
            )
        }
        let usable = nearest.distanceKm <= 35
        let note = usable
            ? "국립해양조사원 \(nearest.station.name)(\(nearest.station.code)) 조석예보를 붙였습니다. 예보지점까지 \(distanceText)km라 시각이 다를 수 있습니다."
            : "\(nearest.station.name) 조석예보는 \(distanceText)km 떨어져 이 자리의 간조로 쓰지 않았습니다. 들물·날물은 바다 예보 모델입니다."
        return TideReport(
            stationName: nearest.station.name,
            stationCode: nearest.station.code,
            distanceKm: nearest.distanceKm,
            samples: samples,
            usable: usable,
            note: note
        )
    }

    private static func load(station: TideStation, from: Date, to: Date, apiKey: String) async -> [TideSample] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: to)
        var samples: [TideSample] = []
        while day <= last {
            let stamp = dayStamp(day, calendar: calendar)
            if let chunk = await oneDay(code: station.code, day: stamp, apiKey: apiKey) {
                samples.append(contentsOf: chunk)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return samples
    }

    private static func oneDay(code: String, day: String, apiKey: String) async -> [TideSample]? {
        var parts = URLComponents(string: "https://apis.data.go.kr/1192136/tideFcstTime/GetTideFcstTimeApiService")
        parts?.queryItems = [
            URLQueryItem(name: "serviceKey", value: apiKey),
            URLQueryItem(name: "type", value: "json"),
            URLQueryItem(name: "obsCode", value: code),
            URLQueryItem(name: "reqDate", value: day),
            URLQueryItem(name: "min", value: "60"),
            URLQueryItem(name: "numOfRows", value: "48"),
            URLQueryItem(name: "pageNo", value: "1"),
        ]
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var items: [[String: Any]] = []
        collect(object, into: &items)
        let samples = items.compactMap(sample)
        return samples.isEmpty ? nil : samples
    }

    private static func collect(_ value: Any, into items: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if dict["predcDt"] != nil || dict["tdlvHgt"] != nil {
                items.append(dict)
            }
            for child in dict.values {
                collect(child, into: &items)
            }
        } else if let list = value as? [Any] {
            for child in list {
                collect(child, into: &items)
            }
        }
    }

    private static func sample(_ item: [String: Any]) -> TideSample? {
        let rawTime = item["predcDt"] as? String ?? ""
        guard let time = parse(rawTime) else { return nil }
        let height: Double?
        if let number = item["tdlvHgt"] as? NSNumber {
            height = number.doubleValue
        } else if let text = item["tdlvHgt"] as? String {
            height = Double(text)
        } else {
            height = nil
        }
        guard let height else { return nil }
        return TideSample(time: time, heightCm: height)
    }

    private static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyyMMddHHmmss", "yyyyMMddHHmm"]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d%02d%02d", year, month, day)
    }
}
