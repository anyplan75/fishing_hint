import Foundation

// 기온·바람·기압은 육지 예보에서, 수온·파도·해수면 높이는 바다 예보에서 가져옵니다.
// 해수면 높이가 오르내리면 들물·날물·만조·간조로 읽습니다.

enum ConditionClient {
    static func fetch(latitude: Double, longitude: Double) async throws -> ConditionPack {
        async let weather = fetchJSON(weatherURL(latitude, longitude))
        async let marine = fetchJSON(marineURL(latitude, longitude))
        let weatherJSON = try await weather
        let marineJSON = try? await marine
        return merge(weather: weatherJSON, marine: marineJSON, latitude: latitude, longitude: longitude)
    }

    private static func weatherURL(_ lat: Double, _ lon: Double) -> URL {
        url("https://api.open-meteo.com/v1/forecast", [
            "latitude": "\(lat)",
            "longitude": "\(lon)",
            "hourly": "temperature_2m,pressure_msl,wind_speed_10m,wind_direction_10m,precipitation,cloud_cover,weather_code",
            "daily": "sunrise,sunset",
            "timezone": "auto",
            "forecast_days": "2",
            "wind_speed_unit": "ms",
        ])
    }

    private static func marineURL(_ lat: Double, _ lon: Double) -> URL {
        url("https://marine-api.open-meteo.com/v1/marine", [
            "latitude": "\(lat)",
            "longitude": "\(lon)",
            "hourly": "sea_surface_temperature,wave_height,sea_level_height_msl",
            "timezone": "auto",
            "forecast_days": "2",
            "cell_selection": "sea",
            "length_unit": "metric",
        ])
    }

    private static func url(_ base: String, _ query: [String: String]) -> URL {
        var parts = URLComponents(string: base)!
        parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    private static func fetchJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private static func merge(weather: [String: Any], marine: [String: Any]?, latitude: Double, longitude: Double) -> ConditionPack {
        let offset = weather["utc_offset_seconds"] as? Int ?? 0
        let hourly = weather["hourly"] as? [String: Any] ?? [:]
        let times = hourly["time"] as? [String] ?? []
        let air = numbers(hourly["temperature_2m"])
        let pressure = numbers(hourly["pressure_msl"])
        let wind = numbers(hourly["wind_speed_10m"])
        let windDir = numbers(hourly["wind_direction_10m"])
        let rain = numbers(hourly["precipitation"])
        let cloud = numbers(hourly["cloud_cover"])
        let code = numbers(hourly["weather_code"])

        let marineHourly = marine?["hourly"] as? [String: Any] ?? [:]
        let marineTimes = marineHourly["time"] as? [String] ?? []
        let sea = numbers(marineHourly["sea_surface_temperature"])
        let wave = numbers(marineHourly["wave_height"])
        let level = numbers(marineHourly["sea_level_height_msl"])
        var marineByTime: [String: Int] = [:]
        for (index, time) in marineTimes.enumerated() { marineByTime[time] = index }

        var cellDistance: Double?
        var usedSea = false
        if let marine, let cellLat = marine["latitude"] as? Double, let cellLon = marine["longitude"] as? Double {
            cellDistance = Geo.kilometers(latitude, longitude, cellLat, cellLon)
            usedSea = (cellDistance ?? 999) <= 25 && sea.contains { $0 != nil }
        }

        var hours: [HourCondition] = []
        for (index, time) in times.enumerated() {
            let marineIndex = marineByTime[time]
            hours.append(HourCondition(
                time: parse(time, offset: offset) ?? Date(),
                airC: value(air, index),
                seaC: usedSea ? value(sea, marineIndex) : nil,
                windMs: value(wind, index),
                windDeg: value(windDir, index),
                pressureHpa: value(pressure, index),
                rainMm: value(rain, index),
                cloud: value(cloud, index),
                weatherCode: value(code, index).map { Int($0) },
                waveM: usedSea ? value(wave, marineIndex) : nil,
                seaLevelM: usedSea ? value(level, marineIndex) : nil,
                tide: .unknown,
                tideRangeM: nil
            ))
        }
        markTide(&hours)
        let daily = weather["daily"] as? [String: Any] ?? [:]
        let sunrise = (daily["sunrise"] as? [String])?.first.flatMap { parse($0, offset: offset) }
        let sunset = (daily["sunset"] as? [String])?.first.flatMap { parse($0, offset: offset) }
        let note = usedSea
            ? "수온·파도·물때는 가장 가까운 바다 칸의 예보입니다."
            : "바다 칸이 멀어 민물·내수면으로 봤습니다. 물때 대신 기온과 시간을 씁니다."
        return ConditionPack(
            hours: hours,
            sunrise: sunrise,
            sunset: sunset,
            seaCellDistanceKm: cellDistance,
            usedSea: usedSea,
            fetchedAt: Date(),
            note: note
        )
    }

    private static func markTide(_ hours: inout [HourCondition]) {
        let known = hours.compactMap(\.seaLevelM)
        guard known.count >= 4, let high = known.max(), let low = known.min() else { return }
        let range = high - low
        for index in hours.indices {
            hours[index].tideRangeM = range
            guard let level = hours[index].seaLevelM else { continue }
            let prev = index > 0 ? hours[index - 1].seaLevelM : nil
            let next = index + 1 < hours.count ? hours[index + 1].seaLevelM : nil
            if let prev, let next, level >= prev, level >= next, level - min(prev, next) > 0.04 {
                hours[index].tide = .high
            } else if let prev, let next, level <= prev, level <= next, max(prev, next) - level > 0.04 {
                hours[index].tide = .low
            } else if let next, next > level + 0.02 {
                hours[index].tide = .flood
            } else if let next, next + 0.02 < level {
                hours[index].tide = .ebb
            } else if let prev, level > prev {
                hours[index].tide = .flood
            } else {
                hours[index].tide = .ebb
            }
        }
    }

    private static func numbers(_ value: Any?) -> [Double?] {
        guard let list = value as? [Any] else { return [] }
        return list.map { item in
            if item is NSNull { return nil }
            return (item as? NSNumber)?.doubleValue
        }
    }

    private static func value(_ list: [Double?], _ index: Int?) -> Double? {
        guard let index, list.indices.contains(index) else { return nil }
        return list[index]
    }

    private static func parse(_ text: String, offset: Int) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }
}
