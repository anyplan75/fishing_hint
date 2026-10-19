import SwiftUI
import WebKit

// 바다해도 탭입니다. 맵박스와 따로, 국립해양조사원이 공개한 오픈레이어스 방식으로 해어름을 봅니다.

private enum ChartPlaceKind: String, CaseIterable, Identifiable {
    case here = "현재 위치"
    case picked = "고른 자리"

    var id: String { rawValue }
}

private struct ChartPlace {
    var title: String
    var latitude: Double
    var longitude: Double
}

struct ChartScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind: ChartPlaceKind = .here
    @State private var facts: [ChartFact] = []
    @State private var mapScript: String?
    @State private var rejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("바다해도")
                .font(.largeTitle.weight(.bold))
            Text("국립해양조사원 해어름을 그들이 공개한 방식으로 봅니다. 맵박스 지도와 겹치지 않습니다. 항해용으로 쓰지 마세요.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            HStack(spacing: 8) {
                ForEach(ChartPlaceKind.allCases) { item in
                    Button(item.rawValue) { kind = item }
                        .buttonStyle(FieldButton(
                            fill: kind == item ? FieldColor.good : FieldColor.card2,
                            ink: kind == item ? FieldColor.ink : FieldColor.paper
                        ))
                }
            }
            if store.dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missingKey
            } else if let rejection {
                FieldCard {
                    Text(rejection)
                        .font(.subheadline)
                }
            } else if let place = chosenPlace() {
                Text("\(place.title) 주변입니다. 수심·위험은 공개 응답에 글이 있을 때만 적습니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                if let mapScript {
                    HaereumMapView(
                        script: mapScript,
                        latitude: place.latitude,
                        longitude: place.longitude
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if !facts.isEmpty {
                    Text("배경 지도를 불러오지 못했습니다.")
                        .font(.subheadline)
                        .foregroundStyle(FieldColor.muted)
                }
                factList
            } else {
                missingPlace
            }
        }
        .padding(16)
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
        .task(id: reloadKey) {
            await reloadFacts()
        }
    }

    private var missingKey: some View {
        FieldCard {
            Text("조석 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다. 키가 없으면 해도를 부르지 않습니다.")
                .font(.subheadline)
        }
    }

    private var missingPlace: some View {
        FieldCard {
            Text(kind == .here
                 ? "현재 위치가 없습니다. 위치 권한을 허용해 주세요."
                 : "고른 자리가 없습니다. 지도 탭에서 자리를 찍거나 저장한 지역을 고르세요.")
                .font(.subheadline)
        }
    }

    private var factList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if facts.isEmpty {
                    Text("이 지점의 글을 가져오는 중입니다.")
                        .font(.caption)
                        .foregroundStyle(FieldColor.muted)
                }
                ForEach(facts) { fact in
                    FieldCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fact.title).font(.headline)
                            ForEach(Array(fact.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.subheadline)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private var reloadKey: String {
        let key = store.dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = chosenPlace()
        let lat = place.map { String(format: "%.4f", $0.latitude) } ?? "-"
        let lon = place.map { String(format: "%.4f", $0.longitude) } ?? "-"
        return "\(kind.rawValue)|\(lat)|\(lon)|\(key.isEmpty)|\(key.hashValue)"
    }

    private func chosenPlace() -> ChartPlace? {
        switch kind {
        case .here:
            guard let latitude = store.userLat, let longitude = store.userLon else { return nil }
            return ChartPlace(title: "현재 위치", latitude: latitude, longitude: longitude)
        case .picked:
            if let tapped = store.tapped {
                return ChartPlace(title: tapped.name, latitude: tapped.latitude, longitude: tapped.longitude)
            }
            if let id = store.selectedPointId {
                if let mine = store.myPoints.first(where: { $0.id == id }) {
                    return ChartPlace(title: mine.name, latitude: mine.latitude, longitude: mine.longitude)
                }
                if let brief = store.briefings[id] {
                    return ChartPlace(title: brief.point.name, latitude: brief.point.latitude, longitude: brief.point.longitude)
                }
            }
            if !store.useMyLocation, let region = store.region {
                return ChartPlace(title: region.name, latitude: region.latitude, longitude: region.longitude)
            }
            return nil
        }
    }

    private func reloadFacts() async {
        let key = store.dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let place = chosenPlace() else {
            facts = []
            mapScript = nil
            rejection = nil
            return
        }
        facts = []
        mapScript = nil
        rejection = nil
        do {
            let page = try await HaereumClient.load(latitude: place.latitude, longitude: place.longitude, apiKey: key)
            rejection = page.rejection
            mapScript = page.script
            facts = page.facts
        } catch is CancellationError {
            return
        } catch {
            rejection = "해도를 불러오지 못했습니다."
            mapScript = nil
            facts = []
        }
    }
}

private struct HaereumMapView: View {
    var script: String
    var latitude: Double
    var longitude: Double

    var body: some View {
        HaereumWebView(script: script, latitude: latitude, longitude: longitude)
    }
}

#if os(iOS)
private struct HaereumWebView: UIViewRepresentable {
    var script: String
    var latitude: Double
    var longitude: Double

    func makeCoordinator() -> HaereumCoordinator { HaereumCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(webView, script: script, latitude: latitude, longitude: longitude)
    }
}
#else
private struct HaereumWebView: NSViewRepresentable {
    var script: String
    var latitude: Double
    var longitude: Double

    func makeCoordinator() -> HaereumCoordinator { HaereumCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(webView, script: script, latitude: latitude, longitude: longitude)
    }
}
#endif

private final class HaereumCoordinator {
    private var signature = ""

    func load(_ webView: WKWebView, script: String, latitude: Double, longitude: Double) {
        let next = String(format: "%.4f,%.4f,%d", latitude, longitude, script.hashValue)
        guard next != signature else { return }
        signature = next
        let html = HaereumPage.html(script: script, latitude: latitude, longitude: longitude)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.khoa.go.kr"))
    }
}

private enum HaereumPage {
    static func html(script: String, latitude: Double, longitude: Double) -> String {
        let source = script.replacingOccurrences(of: "</", with: "<\\/")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body, #map { margin:0; height:100%; background:#071014; }
          #note { position:absolute; left:8px; right:8px; bottom:8px; color:#e8efe6; font:13px -apple-system, sans-serif; }
        </style>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/openlayers/2.13.1/OpenLayers.js"></script>
        <script src="https://www.khoa.go.kr/oceanmap/js/proj4js-1.1.0/lib/proj4js.js"></script>
        <script src="https://www.khoa.go.kr/oceanmap/js/proj4js-1.1.0/lib/defs/EPSG5179.js"></script>
        <script src="https://www.khoa.go.kr/oceanmap/js/gis/OtmsApi.js"></script>
        <script>
        \(source)
        </script>
        </head>
        <body>
        <div id="map"></div>
        <div id="note"></div>
        <script>
        function startChart() {
          var note = document.getElementById("note");
          if (typeof OpenLayers === "undefined" || typeof OtmsLayer === "undefined") {
            note.textContent = "해어름 지도를 불러오지 못했습니다.";
            return;
          }
          if (typeof Proj4js === "undefined" || !Proj4js.defs["EPSG:5179"]) {
            note.textContent = "위치 변환 도구를 불러오지 못했습니다.";
            return;
          }
          OpenLayers.IMAGE_RELOAD_ATTEMPTS = 3;
          OpenLayers.Util.onImageLoadErrorColor = "transparent";
          var map = new OpenLayers.Map("map", {
            projection: new OpenLayers.Projection("EPSG:5179"),
            displayProjection: new OpenLayers.Projection("EPSG:4326"),
            maxExtent: new OpenLayers.Bounds(-200000.0, -3015.4524155292, 3803015.45241553, 4000000.0),
            restrictedExtent: new OpenLayers.Bounds(37953.1466, 1126946.7253, 2152527.8074, 2873292.7040),
            allOverlays: true,
            maxResolution: 1954.597389,
            numZoomLevels: 11,
            layers: [OtmsLayer],
            controls: []
          });
          var center = new OpenLayers.LonLat(\(longitude), \(latitude)).transform(
            new OpenLayers.Projection("EPSG:4326"),
            new OpenLayers.Projection("EPSG:5179")
          );
          map.setCenter(center, 8);
          map.addControl(new OpenLayers.Control.Navigation());
        }
        window.onload = startChart;
        </script>
        </body>
        </html>
        """
    }
}
