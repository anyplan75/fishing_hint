import Foundation

// 국립해양조사원 해어름을 공개 문서에 적힌 주소로만 부릅니다.
// 맵박스 타일로 겹치지 않습니다. 응답에 없는 수심, 위험, 어장은 만들지 않습니다.

struct ChartFact: Identifiable {
    var id: String
    var title: String
    var lines: [String]
}

enum HaereumClient {
    /// 개방海 안내 5장에 적힌 배경 지도 스크립트입니다. 오픈레이어스가 이 주소를 읽어 해도 그림을 만듭니다.
    static let basemapScriptRoot = "https://www.khoa.go.kr/oceanmap/BASEMAP/otmsBasemapApi.do"
    /// K-OCEAN 안내에 적힌 위치 자료 주소입니다. 문서의 http 주소는 포털로 옮겨져, 같은 경로의 https 를 부릅니다.
    private static let featureRoot = "https://www.khoa.go.kr/kocean/wfsApi.do"

    /// 공개 문서에 이름이 있는 자료만 부릅니다.
    private static let layers: [(code: String, title: String)] = [
        ("TB_FACI_BEACH", "해수욕장"),
        ("TB_YACHT_SPOINT", "선상낚시 포인트"),
        ("TL_DIST_FSHFRM", "어장정보"),
    ]

    /// 공개 예시 표에 뜻이 적힌 항목만 한글로 바꿉니다. 그 외 이름은 응답 그대로 둡니다.
    private static let knownLabels = [
        "rgn_nm": "지역",
        "farm_knd": "품종",
        "fids_se": "어업 구분",
        "fids_knd": "어업 종류",
        "fids_mthd": "어업 방법",
        "addr": "주소",
        "area": "면적",
        "lcns_no": "면허번호",
        "admdst_nm": "행정구역",
        "ctpv_nm": "시도",
        "sgg_nm": "시군구",
    ]

    static func basemapScript(apiKey: String) -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        var parts = URLComponents(string: basemapScriptRoot)
        parts?.queryItems = [URLQueryItem(name: "ServiceKey", value: key)]
        return parts?.string
    }

    /// 고른 지점 동서남북 약 2km 안에서, 공개 자료가 글로 준 항목만 모읍니다.
    static func facts(latitude: Double, longitude: Double, apiKey: String) async throws -> [ChartFact] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let south = latitude - 0.02
        let north = latitude + 0.02
        let west = longitude - 0.02
        let east = longitude + 0.02
        var found: [ChartFact] = []
        for layer in layers {
            let fact = try await oneLayer(
                code: layer.code,
                title: layer.title,
                apiKey: key,
                minLon: west,
                minLat: south,
                maxLon: east,
                maxLat: north
            )
            found.append(fact)
        }
        return found
    }

    private static func oneLayer(
        code: String,
        title: String,
        apiKey: String,
        minLon: Double,
        minLat: Double,
        maxLon: Double,
        maxLat: Double
    ) async throws -> ChartFact {
        var parts = URLComponents(string: featureRoot)
        parts?.queryItems = [
            URLQueryItem(name: "ServiceKey", value: apiKey),
            URLQueryItem(name: "Layer", value: code),
            URLQueryItem(name: "minlon", value: degreeText(minLon)),
            URLQueryItem(name: "minlat", value: degreeText(minLat)),
            URLQueryItem(name: "maxlon", value: degreeText(maxLon)),
            URLQueryItem(name: "maxlat", value: degreeText(maxLat)),
            URLQueryItem(name: "srsName", value: "EPSG:4326"),
        ]
        guard let url = parts?.url else {
            return ChartFact(id: code, title: title, lines: ["주소를 만들지 못했습니다. 없는 내용은 적지 않습니다."])
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 400 {
                return ChartFact(id: code, title: title, lines: ["호출이 실패했습니다. 없는 내용은 적지 않습니다."])
            }
            if data.count > 1_500_000 {
                return ChartFact(id: code, title: title, lines: ["응답이 너무 커서 이 지점의 글만 골라 내지 못했습니다. 없는 내용은 적지 않습니다."])
            }
            return read(data: data, code: code, title: title)
        } catch {
            if error is CancellationError { throw error }
            return ChartFact(id: code, title: title, lines: ["자료를 가져오지 못했습니다. 없는 내용은 적지 않습니다."])
        }
    }

    /// 공개 문서의 도^분^초 형식입니다.
    private static func degreeText(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        var absolute = abs(value)
        var degree = Int(absolute)
        absolute = (absolute - Double(degree)) * 60
        var minute = Int(absolute)
        var second = Int(((absolute - Double(minute)) * 60).rounded())
        if second == 60 {
            second = 0
            minute += 1
        }
        if minute == 60 {
            minute = 0
            degree += 1
        }
        return "\(sign)\(degree)^\(minute)^\(second)"
    }

    private static func read(data: Data, code: String, title: String) -> ChartFact {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let result = object["result"] as? String {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = trimmed.isEmpty ? "응답에 글 항목이 없습니다." : "공개 자료 응답: \(trimmed)"
            return ChartFact(id: code, title: title, lines: [line])
        }
        let parser = HaereumFeatureParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            return ChartFact(id: code, title: title, lines: ["응답을 글로 읽지 못했습니다. 없는 내용은 적지 않습니다."])
        }
        if parser.rows.isEmpty {
            return ChartFact(id: code, title: title, lines: ["이 지점 주변에서 준 글 항목이 없습니다."])
        }
        var lines: [String] = []
        for (index, row) in parser.rows.prefix(3).enumerated() {
            if parser.rows.count > 1 {
                lines.append("\(index + 1)번째")
            }
            if row.isEmpty {
                lines.append("위치만 있고 글 항목은 없습니다.")
                continue
            }
            for pair in row {
                let label = Self.knownLabels[pair.name] ?? pair.name
                lines.append("\(label): \(pair.value)")
            }
        }
        if parser.rows.count > 3 {
            lines.append("같은 자료가 \(parser.rows.count)건입니다. 위 3건만 적었습니다.")
        }
        return ChartFact(id: code, title: title, lines: lines)
    }
}

private struct FeatureField {
    var name: String
    var value: String
}

fileprivate final class HaereumFeatureParser: NSObject, XMLParserDelegate {
    var rows: [[FeatureField]] = []
    private var depth = 0
    private var wrapperDepth = 0
    private var bodyDepth = 0
    private var currentText = ""
    private var row: [FeatureField] = []
    private var insideFeature = false
    private let skip: Set<String> = [
        "posList", "lowerCorner", "upperCorner", "pos", "coordinates",
        "exterior", "interior", "LinearRing", "Polygon", "MultiSurface",
        "surfaceMember", "Envelope", "boundedBy", "ag_geom", "featureMember", "featureMembers",
    ]

    @objc func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        depth += 1
        let name = local(elementName)
        if name == "featureMember" || name == "featureMembers" {
            insideFeature = true
            wrapperDepth = depth
            bodyDepth = 0
            row = []
        } else if insideFeature, bodyDepth == 0, depth == wrapperDepth + 1 {
            bodyDepth = depth
            row = []
        }
        currentText = ""
    }

    @objc func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    @objc func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = local(elementName)
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideFeature, bodyDepth > 0, depth > bodyDepth, !value.isEmpty, !skip.contains(name), !looksLikeCoordinates(value) {
            row.append(FeatureField(name: name, value: value))
        }
        if insideFeature, bodyDepth > 0, depth == bodyDepth {
            if rows.count < 8 {
                rows.append(row)
            }
            row = []
            bodyDepth = 0
        }
        if (name == "featureMember" || name == "featureMembers"), depth == wrapperDepth {
            insideFeature = false
        }
        currentText = ""
        depth -= 1
    }

    private func local(_ name: String) -> String {
        if let colon = name.lastIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }

    private func looksLikeCoordinates(_ value: String) -> Bool {
        let parts = value.split(separator: " ")
        guard parts.count > 4 else { return false }
        return parts.allSatisfy { Double($0) != nil }
    }
}
