import SwiftUI
import WebKit

// 맵박스 공식 지도 엔진으로 지도를 그립니다.
// 내 위치는 폰·맥이 재서 지도 위에 올립니다. 지도 암호는 빌드할 때 넣은 값을 읽습니다.

struct MapPin: Identifiable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var score: Int
    var selected: Bool
}

struct MapboxMapView: View {
    var token: String
    var latitude: Double
    var longitude: Double
    var userLat: Double?
    var userLon: Double?
    var radiusKm: Double
    var flyToken: Int
    var pins: [MapPin]
    var onTap: (Double, Double) -> Void
    var onSelect: (String) -> Void
    var onMove: (Double, Double) -> Void
    var onMap: (Bool) -> Void

    var body: some View {
        MapboxWebView(
            token: token,
            latitude: latitude,
            longitude: longitude,
            userLat: userLat,
            userLon: userLon,
            radiusKm: radiusKm,
            flyToken: flyToken,
            pins: pins,
            onTap: onTap,
            onSelect: onSelect,
            onMove: onMove,
            onMap: onMap
        )
    }
}

#if os(iOS)
private struct MapboxWebView: UIViewRepresentable {
    var token: String
    var latitude: Double
    var longitude: Double
    var userLat: Double?
    var userLon: Double?
    var radiusKm: Double
    var flyToken: Int
    var pins: [MapPin]
    var onTap: (Double, Double) -> Void
    var onSelect: (String) -> Void
    var onMove: (Double, Double) -> Void
    var onMap: (Bool) -> Void

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(onTap: onTap, onSelect: onSelect, onMove: onMove, onMap: onMap)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: context.coordinator.configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(MapPage.html, baseURL: URL(string: "https://api.mapbox.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onSelect = onSelect
        context.coordinator.onMove = onMove
        context.coordinator.onMap = onMap
        context.coordinator.push(webView, state: currentState())
    }

    private func currentState() -> MapState {
        MapState(token: token, latitude: latitude, longitude: longitude, userLat: userLat, userLon: userLon, radiusKm: radiusKm, flyToken: flyToken, pins: pins)
    }
}
#else
private struct MapboxWebView: NSViewRepresentable {
    var token: String
    var latitude: Double
    var longitude: Double
    var userLat: Double?
    var userLon: Double?
    var radiusKm: Double
    var flyToken: Int
    var pins: [MapPin]
    var onTap: (Double, Double) -> Void
    var onSelect: (String) -> Void
    var onMove: (Double, Double) -> Void
    var onMap: (Bool) -> Void

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(onTap: onTap, onSelect: onSelect, onMove: onMove, onMap: onMap)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: context.coordinator.configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(MapPage.html, baseURL: URL(string: "https://api.mapbox.com"))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onSelect = onSelect
        context.coordinator.onMove = onMove
        context.coordinator.onMap = onMap
        context.coordinator.push(webView, state: currentState())
    }

    private func currentState() -> MapState {
        MapState(token: token, latitude: latitude, longitude: longitude, userLat: userLat, userLon: userLon, radiusKm: radiusKm, flyToken: flyToken, pins: pins)
    }
}
#endif

private struct MapState {
    var token: String
    var latitude: Double
    var longitude: Double
    var userLat: Double?
    var userLon: Double?
    var radiusKm: Double
    var flyToken: Int
    var pins: [MapPin]

    var zoom: Double {
        let value = 14 - log2(max(radiusKm, 1) / 2)
        return min(14.5, max(8, value))
    }

    var json: String {
        var pinObjects: [[String: Any]] = []
        for pin in pins {
            pinObjects.append([
                "id": pin.id,
                "name": pin.name,
                "lat": pin.latitude,
                "lon": pin.longitude,
                "score": pin.score,
                "selected": pin.selected,
            ])
        }
        var object: [String: Any] = [
            "token": token,
            "lat": latitude,
            "lon": longitude,
            "radius": radiusKm * 1000,
            "zoom": zoom,
            "fly": flyToken,
            "pins": pinObjects,
        ]
        if let userLat, let userLon {
            object["userLat"] = userLat
            object["userLon"] = userLon
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

final class MapCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var onTap: (Double, Double) -> Void
    var onSelect: (String) -> Void
    var onMove: (Double, Double) -> Void
    var onMap: (Bool) -> Void
    let configuration = WKWebViewConfiguration()
    private weak var webView: WKWebView?
    private var ready = false
    private var lastJSON = ""
    private var lastFly = -1

    init(onTap: @escaping (Double, Double) -> Void, onSelect: @escaping (String) -> Void, onMove: @escaping (Double, Double) -> Void, onMap: @escaping (Bool) -> Void) {
        self.onTap = onTap
        self.onSelect = onSelect
        self.onMove = onMove
        self.onMap = onMap
        super.init()
        configuration.userContentController.add(self, name: "naksi")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        self.webView = webView
        deliver()
    }

    fileprivate func push(_ webView: WKWebView, state: MapState) {
        self.webView = webView
        let fly = state.flyToken != lastFly
        if fly { lastFly = state.flyToken }
        lastJSON = state.json
        if ready { deliver(forceFly: fly) }
    }

    private func deliver(forceFly: Bool = false) {
        guard ready, let webView else { return }
        let flyFlag = forceFly ? "true" : "false"
        webView.evaluateJavaScript("window.applyState(\(lastJSON), \(flyFlag))") { _, _ in }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "tap", let lat = Self.number(body["lat"]), let lon = Self.number(body["lon"]) {
            DispatchQueue.main.async { self.onTap(lat, lon) }
        } else if type == "select", let id = body["id"] as? String {
            DispatchQueue.main.async { self.onSelect(id) }
        } else if type == "move", let lat = Self.number(body["lat"]), let lon = Self.number(body["lon"]) {
            DispatchQueue.main.async { self.onMove(lat, lon) }
        } else if type == "map" {
            let ok = body["ok"] as? Bool ?? false
            DispatchQueue.main.async { self.onMap(ok) }
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

private enum MapPage {
    static let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <link href="https://api.mapbox.com/mapbox-gl-js/v3.17.0/mapbox-gl.css" rel="stylesheet">
    <script src="https://api.mapbox.com/mapbox-gl-js/v3.17.0/mapbox-gl.js"></script>
    <style>
      html, body, #map { margin:0; height:100%; background:#071018; }
      .mapboxgl-ctrl-attrib { font-size:10px; }
    </style>
    </head>
    <body>
    <div id="map"></div>
    <script>
    let map = null;
    let ready = false;
    function post(obj){ if (window.webkit && window.webkit.messageHandlers.naksi) window.webkit.messageHandlers.naksi.postMessage(obj); }
    function circle(lon, lat, radius) {
      const steps = 64, coords = [];
      for (let i = 0; i <= steps; i++) {
        const a = (i / steps) * Math.PI * 2;
        const dx = radius * Math.cos(a);
        const dy = radius * Math.sin(a);
        const dLat = dy / 111320;
        const dLon = dx / (111320 * Math.cos(lat * Math.PI / 180));
        coords.push([lon + dLon, lat + dLat]);
      }
      return coords;
    }
    function color(score){ if (score >= 75) return '#d6f25c'; if (score >= 60) return '#8fd3ff'; return '#ff6b4a'; }
    function ensure(token, lon, lat, zoom) {
      if (map || !token) return;
      mapboxgl.accessToken = token;
      map = new mapboxgl.Map({ container:'map', style:'mapbox://styles/mapbox/outdoors-v12', center:[lon, lat], zoom:zoom });
      map.addControl(new mapboxgl.NavigationControl({ showCompass:true }), 'bottom-right');
      map.addControl(new mapboxgl.ScaleControl({ unit:'metric' }), 'bottom-left');
        map.on('error', (event) => {
        const status = event && event.error && event.error.status;
        if (status === 401 || status === 403) post({ type:'map', ok:false });
      });
      map.on('load', () => {
        ready = true;
        post({ type:'map', ok:true });
        if (map.setLanguage) { try { map.setLanguage('ko'); } catch (e) {} }
        map.addSource('radius', { type:'geojson', data:{ type:'FeatureCollection', features:[] } });
        map.addLayer({ id:'radius-fill', type:'fill', source:'radius', paint:{ 'fill-color':'#1c8c86', 'fill-opacity':0.12 } });
        map.addLayer({ id:'radius-line', type:'line', source:'radius', paint:{ 'line-color':'#d6f25c', 'line-width':1.4 } });
        map.addSource('pins', { type:'geojson', data:{ type:'FeatureCollection', features:[] } });
        map.addLayer({ id:'pins', type:'circle', source:'pins', paint:{
          'circle-radius':['case', ['get','selected'], 11, 8],
          'circle-color':['get','color'],
          'circle-stroke-width':2,
          'circle-stroke-color':'#071018'
        }});
        map.addSource('user', { type:'geojson', data:{ type:'FeatureCollection', features:[] } });
        map.addLayer({ id:'user', type:'circle', source:'user', paint:{ 'circle-radius':7, 'circle-color':'#ffffff', 'circle-stroke-width':3, 'circle-stroke-color':'#1c8c86' } });
        map.on('click', 'pins', (event) => {
          const feature = event.features && event.features[0];
          if (!feature) return;
          event.originalEvent && event.originalEvent.stopPropagation && event.originalEvent.preventDefault();
          post({ type:'select', id: feature.properties.id });
        });
        map.on('click', (event) => {
          const hits = map.queryRenderedFeatures(event.point, { layers:['pins'] });
          if (hits.length) return;
          post({ type:'tap', lat: event.lngLat.lat, lon: event.lngLat.lng });
        });
        map.on('moveend', () => {
          const c = map.getCenter();
          post({ type:'move', lat: c.lat, lon: c.lng });
        });
        if (window.__pending) window.applyState(window.__pending, window.__pendingFly);
      });
    }
    window.applyState = function(state, fly) {
      window.__pending = state;
      window.__pendingFly = fly;
      if (!state || !state.token) return;
      ensure(state.token, state.lon, state.lat, state.zoom);
      if (!map || !ready) return;
      if (fly) map.flyTo({ center:[state.lon, state.lat], zoom: state.zoom });
      const ring = circle(state.lon, state.lat, state.radius);
      map.getSource('radius').setData({ type:'Feature', geometry:{ type:'Polygon', coordinates:[ring] } });
      const features = (state.pins || []).map(pin => ({
        type:'Feature',
        properties:{ id: pin.id, name: pin.name, score: pin.score, selected: !!pin.selected, color: color(pin.score) },
        geometry:{ type:'Point', coordinates:[pin.lon, pin.lat] }
      }));
      map.getSource('pins').setData({ type:'FeatureCollection', features: features });
      const userFeatures = (state.userLat == null) ? [] : [{
        type:'Feature', properties:{}, geometry:{ type:'Point', coordinates:[state.userLon, state.userLat] }
      }];
      map.getSource('user').setData({ type:'FeatureCollection', features: userFeatures });
    };
    </script>
    </body>
    </html>
    """
}
