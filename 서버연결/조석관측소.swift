// 국립해양조사원 조위관측소 운영 현황 공개 파일에서 이름과 좌표만 옮겼습니다.
// 출처는 공공데이터포털 자료 15146602 입니다. 조석 높이를 부를 때 가장 가까운 곳을 고릅니다.

struct TideStation {
    var code: String
    var name: String
    var latitude: Double
    var longitude: Double
}

enum TideStationBook {
    static let stations: [TideStation] = [
        TideStation(code: "DT_0002", name: "평택", latitude: 36.966944, longitude: 126.822778),
        TideStation(code: "DT_0003", name: "영광", latitude: 35.426111, longitude: 126.420556),
        TideStation(code: "DT_0004", name: "제주", latitude: 33.527500, longitude: 126.543056),
        TideStation(code: "DT_0005", name: "부산", latitude: 35.096389, longitude: 129.035278),
        TideStation(code: "DT_0006", name: "묵호", latitude: 37.550278, longitude: 129.116389),
        TideStation(code: "DT_0007", name: "목포", latitude: 34.779722, longitude: 126.375556),
        TideStation(code: "DT_0008", name: "안산", latitude: 37.192222, longitude: 126.647222),
        TideStation(code: "DT_0010", name: "서귀포", latitude: 33.240000, longitude: 126.561667),
        TideStation(code: "DT_0011", name: "후포", latitude: 36.677500, longitude: 129.453056),
        TideStation(code: "DT_0012", name: "속초", latitude: 38.207222, longitude: 128.594167),
        TideStation(code: "DT_0013", name: "울릉도", latitude: 37.491389, longitude: 130.913611),
        TideStation(code: "DT_0016", name: "여수", latitude: 34.747222, longitude: 127.765556),
        TideStation(code: "DT_0017", name: "대산", latitude: 37.007500, longitude: 126.352778),
        TideStation(code: "DT_0018", name: "군산", latitude: 35.975556, longitude: 126.563056),
        TideStation(code: "DT_0021", name: "추자도", latitude: 33.961944, longitude: 126.300278),
        TideStation(code: "DT_0023", name: "모슬포", latitude: 33.214444, longitude: 126.251111),
        TideStation(code: "DT_0028", name: "진도", latitude: 34.377778, longitude: 126.308611),
        TideStation(code: "DT_0030", name: "위도(구)", latitude: 35.618056, longitude: 126.301667),
        TideStation(code: "DT_0032", name: "강화대교", latitude: 37.731944, longitude: 126.522222),
        TideStation(code: "DT_0019", name: "가덕도(구)", latitude: 35.024167, longitude: 128.810833),
        TideStation(code: "DT_0020", name: "울산", latitude: 35.501944, longitude: 129.387222),
        TideStation(code: "DT_0022", name: "성산포", latitude: 33.474722, longitude: 126.927778),
        TideStation(code: "DT_0024", name: "장항", latitude: 36.006944, longitude: 126.687500),
        TideStation(code: "DT_0026", name: "고흥발포", latitude: 34.481111, longitude: 127.342778),
        TideStation(code: "DT_0027", name: "완도", latitude: 34.315556, longitude: 126.759722),
        TideStation(code: "DT_0029", name: "거제도", latitude: 34.801389, longitude: 128.699167),
        TideStation(code: "DT_0031", name: "거문도", latitude: 34.028333, longitude: 127.308889),
        TideStation(code: "DT_0035", name: "흑산도", latitude: 34.684167, longitude: 125.435556),
        TideStation(code: "DT_0044", name: "영종대교", latitude: 37.545556, longitude: 126.584444),
        TideStation(code: "DT_0050", name: "태안", latitude: 36.913056, longitude: 126.238889),
        TideStation(code: "DT_0051", name: "서천마량", latitude: 36.128889, longitude: 126.495278),
        TideStation(code: "DT_0049", name: "광양", latitude: 34.903672, longitude: 127.754836),
        TideStation(code: "DT_0056", name: "부산항신항", latitude: 35.077500, longitude: 128.786944),
        TideStation(code: "DT_0057", name: "동해항", latitude: 37.494722, longitude: 129.143889),
        TideStation(code: "DT_0055", name: "순천만", latitude: 34.884111, longitude: 127.512556),
        TideStation(code: "DT_0058", name: "경인항", latitude: 37.560833, longitude: 126.601111),
        TideStation(code: "DT_0038", name: "굴업도", latitude: 37.194444, longitude: 125.995000),
        TideStation(code: "DT_0025", name: "보령", latitude: 36.406389, longitude: 126.486111),
        TideStation(code: "DT_0034", name: "안흥(구)", latitude: 36.673611, longitude: 126.132222),
        TideStation(code: "DT_0001", name: "인천", latitude: 37.451944, longitude: 126.592222),
        TideStation(code: "DT_0052", name: "인천송도", latitude: 37.338056, longitude: 126.586111),
        TideStation(code: "DT_0014", name: "통영", latitude: 34.827778, longitude: 128.434722),
        TideStation(code: "DT_0037", name: "어청도", latitude: 36.117222, longitude: 125.984722),
        TideStation(code: "DT_0009", name: "포항(과거)", latitude: 36.047222, longitude: 129.383889),
        TideStation(code: "DT_0043", name: "영흥도", latitude: 37.238611, longitude: 126.428611),
        TideStation(code: "DT_0061", name: "삼천포", latitude: 34.924167, longitude: 128.069722),
        TideStation(code: "DT_0901", name: "포항_구", latitude: 36.051581, longitude: 129.374499),
        TideStation(code: "DT_0068", name: "위도", latitude: 35.618084, longitude: 126.301816),
        TideStation(code: "DT_0065", name: "덕적도", latitude: 37.226333, longitude: 126.156556),
        TideStation(code: "DT_0066", name: "향화도", latitude: 35.167667, longitude: 126.359556),
        TideStation(code: "DT_0067", name: "안흥", latitude: 36.674639, longitude: 126.129556),
        TideStation(code: "DT_0091", name: "포항", latitude: 36.047128, longitude: 129.383806),
        TideStation(code: "DT_0063", name: "가덕도", latitude: 35.024178, longitude: 128.810933),
        TideStation(code: "DT_0062", name: "마산", latitude: 35.197500, longitude: 128.576389),
        TideStation(code: "DT_0092", name: "여호항", latitude: 34.661944, longitude: 127.469167),
        TideStation(code: "DT_0094", name: "서거차도", latitude: 34.251422, longitude: 125.915450),
        TideStation(code: "DT_0093", name: "소무의도", latitude: 37.373069, longitude: 126.440066),
    ]

    static func nearest(latitude: Double, longitude: Double) -> (station: TideStation, distanceKm: Double)? {
        stations
            .map { station in
                (station: station, distanceKm: Geo.kilometers(latitude, longitude, station.latitude, station.longitude))
            }
            .min { $0.distanceKm < $1.distanceKm }
    }
}
