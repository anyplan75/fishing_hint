import CoreLocation
import Foundation

// 위치, 저장 자료, 지도 중심, 포인트 점수를 한곳에서 다룹니다.

final class LocationFixer: NSObject, CLLocationManagerDelegate {
    var onFix: (@MainActor (CLLocationCoordinate2D) -> Void)?
    var onStatus: (@MainActor (CLAuthorizationStatus) -> Void)?
    var onFail: (@MainActor () -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.onStatus?(status) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.onFix?(coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.onFail?() }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var mapboxToken = ""
    @Published var geminiKey = ""
    @Published var radiusKm = 12.0
    @Published var useMyLocation = true
    @Published var preferSpecies: [String] = []
    @Published var region: SavedRegion?
    @Published var myPoints: [FishingPoint] = []
    @Published var nearby: [FishingPoint] = []
    @Published var tapped: FishingPoint?
    @Published var briefings: [String: PointBriefing] = [:]
    @Published var selectedPointId: String?
    @Published var centerLat = 37.45
    @Published var centerLon = 126.59
    @Published var userLat: Double?
    @Published var userLon: Double?
    @Published var locationText = "위치를 확인하는 중"
    @Published var statusText = "지도를 준비하고 있습니다."
    @Published var busy = false
    @Published var flyToken = 0
    @Published var searchHits: [PlaceNameClient.Hit] = []
    @Published var regionTitle = "선택한 지역"
    @Published var dataGoKrKey = ""
    @Published var planPicks: [SpotPick] = []
    @Published var nowPicks: [SpotPick] = []
    @Published var shorePicks: [SpotPick] = []
    @Published var skinPicks: [SpotPick] = []
    @Published var planMessage = "날짜와 갈 수 있는 시간만 고르면, 그 안에서 좋은 시간을 찾아 최대 10곳을 줄 세웁니다."
    @Published var nowMessage = "지금 위치에서 6시간 안의 좋은 시간을 찾아 최대 3곳을 줄 세웁니다."
    @Published var gleanMessage = "해루질은 낚시 추천과 따로 봅니다. 주간과 야간을 고른 뒤 갯가와 수중을 나눠 보여 줍니다."
    @Published var recommendBusy = false
    @Published var selectedPickId: String?

    private let locator = LocationFixer()
    private var cache: [String: ConditionPack] = [:]
    private var refreshGen = 0
    private var recommendGen = 0
    private var didFirstFix = false

    var ranked: [PointBriefing] {
        briefings.values.sorted { left, right in
            if left.score == right.score {
                return (left.distanceKm ?? 999) < (right.distanceKm ?? 999)
            }
            return left.score > right.score
        }
    }

    func start() {
        loadDisk()
        let secrets = SecretVault.load()
        if mapboxToken.isEmpty { mapboxToken = secrets.mapbox }
        if geminiKey.isEmpty { geminiKey = secrets.gemini }
        if dataGoKrKey.isEmpty { dataGoKrKey = secrets.dataGoKr }
        locator.onFix = { [weak self] coordinate in
            self?.applyFix(coordinate)
        }
        locator.onStatus = { [weak self] status in
            self?.applyStatus(status)
        }
        locator.onFail = { [weak self] in
            self?.locationText = "위치를 가져오지 못했습니다. 지도를 옮겨 지역을 정하세요."
        }
        locator.start()
        if !useMyLocation, let region {
            centerLat = region.latitude
            centerLon = region.longitude
            radiusKm = region.radiusKm
            regionTitle = region.name
            flyToken += 1
            refresh()
        }
    }

    func applyFix(_ coordinate: CLLocationCoordinate2D) {
        let moved: Double
        if let userLat, let userLon {
            moved = Geo.kilometers(userLat, userLon, coordinate.latitude, coordinate.longitude)
        } else {
            moved = 999
        }
        guard moved >= 0.03 || !didFirstFix else { return }
        userLat = coordinate.latitude
        userLon = coordinate.longitude
        locationText = "현재 위치를 사용 중"
        guard useMyLocation else { return }
        if !didFirstFix || moved > 2 {
            didFirstFix = true
            centerLat = coordinate.latitude
            centerLon = coordinate.longitude
            flyToken += 1
            refresh()
        }
    }

    func applyStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationText = "현재 위치를 사용 중"
        case .denied, .restricted:
            locationText = "위치 권한이 꺼져 있습니다"
            statusText = "지도를 옮긴 뒤 '이 지역 분석'을 누르세요."
            if !didFirstFix && briefings.isEmpty && !busy {
                refresh()
            }
        case .notDetermined:
            locationText = "위치 권한을 기다리는 중"
        @unknown default:
            break
        }
    }

    func refresh() {
        refreshGen += 1
        let gen = refreshGen
        let lat = centerLat
        let lon = centerLon
        let radius = radiusKm
        busy = true
        statusText = "주변 자리와 물때, 수온을 계산하는 중"
        Task {
            async let foundCall = NearbyFinder.search(latitude: lat, longitude: lon, radiusKm: radius)
            async let packCall = cachedConditions(latitude: lat, longitude: lon)
            async let nameCall = PlaceNameClient.reverse(latitude: lat, longitude: lon, token: mapboxToken)
            var found: [FishingPoint] = []
            do {
                found = try await foundCall
            } catch {
                found = []
            }
            let pack = try? await packCall
            let title = await nameCall
            guard gen == self.refreshGen else { return }
            if let title, !title.isEmpty { regionTitle = title }
            nearby = found
            guard let pack else {
                busy = false
                statusText = "날씨와 바다 정보를 가져오지 못했습니다. 인터넷을 확인한 뒤 다시 분석하세요."
                return
            }
            await analyze(center: pack, latitude: lat, longitude: lon, generation: gen)
            guard gen == self.refreshGen else { return }
            busy = false
            if ranked.isEmpty {
                statusText = "공개된 자리가 없습니다. 지도를 누르면 그 자리를 바로 분석합니다."
            } else {
                statusText = "\(ranked.count)곳을 조건 점수로 줄 세웠습니다."
            }
            saveDisk()
        }
    }

    func analyzeTap(latitude: Double, longitude: Double) {
        let point = FishingPoint(
            id: String(format: "tap-%.4f-%.4f", latitude, longitude),
            name: "지금 찍은 자리",
            latitude: latitude,
            longitude: longitude,
            place: .custom,
            water: .unknown,
            source: "찍은자리",
            bottom: "",
            targetMemo: "",
            measuredTempC: nil,
            memo: ""
        )
        tapped = point
        selectedPointId = point.id
        statusText = "찍은 자리의 물때와 수온을 계산하는 중"
        Task {
            do {
                let pack = try await cachedConditions(latitude: latitude, longitude: longitude)
                let moon = MoonClock.info(on: Date(), longitude: longitude)
                var briefing = FishingAnalyst.brief(
                    point: point,
                    conditions: pack,
                    moon: moon,
                    preferred: preferSpecies,
                    distanceKm: distance(from: point)
                )
                briefings[point.id] = briefing
                if !geminiKey.isEmpty {
                    if let text = try? await BriefingClient.rewrite(script: briefing.script, apiKey: geminiKey) {
                        briefing.aiScript = text
                        briefings[point.id] = briefing
                    }
                }
            } catch {
                statusText = "이 자리의 날씨를 가져오지 못했습니다."
            }
        }
    }

    func focusOnMe() {
        useMyLocation = true
        guard let userLat, let userLon else {
            statusText = "아직 내 위치가 없습니다. 위치 권한을 허용하세요."
            return
        }
        centerLat = userLat
        centerLon = userLon
        flyToken += 1
        saveDisk()
        refresh()
    }

    func useSavedRegion() {
        guard let region else {
            statusText = "저장된 지역이 없습니다. 지도를 맞춘 뒤 이 지역을 저장하세요."
            return
        }
        useMyLocation = false
        centerLat = region.latitude
        centerLon = region.longitude
        radiusKm = region.radiusKm
        regionTitle = region.name
        flyToken += 1
        saveDisk()
        refresh()
    }

    func saveCurrentRegion() {
        region = SavedRegion(name: regionTitle, latitude: centerLat, longitude: centerLon, radiusKm: radiusKm)
        useMyLocation = false
        statusText = "\(regionTitle) 지역을 저장했습니다."
        saveDisk()
    }

    func rememberMap(latitude: Double, longitude: Double) {
        centerLat = latitude
        centerLon = longitude
    }

    func searchPlaces(_ query: String) {
        Task {
            searchHits = await PlaceNameClient.forward(
                query: query,
                latitude: centerLat,
                longitude: centerLon,
                token: mapboxToken
            )
        }
    }

    func go(to hit: PlaceNameClient.Hit) {
        centerLat = hit.latitude
        centerLon = hit.longitude
        regionTitle = hit.name
        useMyLocation = false
        searchHits = []
        flyToken += 1
        saveDisk()
        refresh()
    }

    func select(_ id: String) {
        selectedPointId = id
        if briefings[id] != nil {
            Task { await polish(id: id, generation: refreshGen) }
            return
        }
        let point = myPoints.first { $0.id == id } ?? (tapped?.id == id ? tapped : nil)
        guard let point else { return }
        Task {
            guard let pack = try? await cachedConditions(latitude: point.latitude, longitude: point.longitude) else {
                statusText = "이 포인트의 날씨를 가져오지 못했습니다."
                return
            }
            let moon = MoonClock.info(on: Date(), longitude: point.longitude)
            var briefing = FishingAnalyst.brief(
                point: point,
                conditions: pack,
                moon: moon,
                preferred: preferSpecies,
                distanceKm: distance(from: point)
            )
            if !geminiKey.isEmpty, let text = try? await BriefingClient.rewrite(script: briefing.script, apiKey: geminiKey) {
                briefing.aiScript = text
            }
            briefings[point.id] = briefing
        }
    }

    func saveMine(from point: FishingPoint) {
        var copy = point
        if copy.source != "내포인트" {
            copy.id = "mine-\(UUID().uuidString)"
            copy.source = "내포인트"
        }
        myPoints.removeAll { $0.id == point.id || ($0.latitude == copy.latitude && $0.longitude == copy.longitude && $0.name == copy.name) }
        myPoints.append(copy)
        if var briefing = briefings[point.id] {
            briefing.point = copy
            briefings.removeValue(forKey: point.id)
            briefings[copy.id] = briefing
        }
        selectedPointId = copy.id
        if tapped?.id == point.id { tapped = copy }
        saveDisk()
    }

    func updateMine(_ point: FishingPoint) {
        guard let index = myPoints.firstIndex(where: { $0.id == point.id }) else { return }
        myPoints[index] = point
        saveDisk()
        Task {
            guard let pack = try? await cachedConditions(latitude: point.latitude, longitude: point.longitude) else { return }
            let moon = MoonClock.info(on: Date(), longitude: point.longitude)
            var briefing = FishingAnalyst.brief(
                point: point,
                conditions: pack,
                moon: moon,
                preferred: preferSpecies,
                distanceKm: distance(from: point)
            )
            if !geminiKey.isEmpty, let text = try? await BriefingClient.rewrite(script: briefing.script, apiKey: geminiKey) {
                briefing.aiScript = text
            }
            briefings[point.id] = briefing
        }
    }

    func deleteMine(_ point: FishingPoint) {
        myPoints.removeAll { $0.id == point.id }
        briefings.removeValue(forKey: point.id)
        if selectedPointId == point.id { selectedPointId = nil }
        saveDisk()
    }

    func keepRadius() {
        saveDisk()
    }

    func saveSecrets() {
        SecretVault.save(SecretPair(
            mapbox: mapboxToken.trimmingCharacters(in: .whitespacesAndNewlines),
            gemini: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            dataGoKr: dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        mapboxToken = mapboxToken.trimmingCharacters(in: .whitespacesAndNewlines)
        geminiKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        dataGoKrKey = dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        statusText = "암호를 이 기기의 열쇠고에 저장했습니다."
    }

    func importSecrets(from url: URL) {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            statusText = "비밀 파일을 읽지 못했습니다."
            return
        }
        let pair = SecretVault.parse(text)
        if !pair.mapbox.isEmpty { mapboxToken = pair.mapbox }
        if !pair.gemini.isEmpty { geminiKey = pair.gemini }
        if !pair.dataGoKr.isEmpty { dataGoKrKey = pair.dataGoKr }
        saveSecrets()
    }

    func toggleSpecies(_ name: String) {
        if let index = preferSpecies.firstIndex(of: name) {
            preferSpecies.remove(at: index)
        } else {
            preferSpecies.append(name)
        }
        saveDisk()
        refresh()
    }

    func pick(id: String) -> SpotPick? {
        planPicks.first { $0.id == id }
            ?? nowPicks.first { $0.id == id }
            ?? shorePicks.first { $0.id == id }
            ?? skinPicks.first { $0.id == id }
    }

    func recommendPlan(on day: Date, startHour: Int, endHour: Int, scope: RecommendScope) {
        let span = RecommendEngine.window(on: day, startHour: startHour, endHour: endHour)
        beginRecommend(scope: scope, requireUser: false, from: span.start, to: span.end, slot: .plan) { context, generation in
            let outcome = RecommendEngine.fishing(
                points: context.points,
                from: context.from,
                to: context.to,
                limit: 10,
                preferred: self.preferSpecies,
                tide: context.tide,
                areaTitle: context.title,
                kind: .plan
            )
            guard generation == self.recommendGen else { return }
            self.planPicks = outcome.picks
            self.planMessage = outcome.message
            self.recommendBusy = false
            await self.polish(outcome.picks, generation: generation)
        }
    }

    func recommendNow() {
        let start = Date()
        let end = start.addingTimeInterval(RecommendEngine.nowSpan)
        beginRecommend(scope: .here, requireUser: true, from: start, to: end, slot: .now) { context, generation in
            let outcome = RecommendEngine.fishing(
                points: context.points,
                from: context.from,
                to: context.to,
                limit: 3,
                preferred: self.preferSpecies,
                tide: context.tide,
                areaTitle: context.title,
                kind: .now
            )
            guard generation == self.recommendGen else { return }
            self.nowPicks = outcome.picks
            self.nowMessage = outcome.message
            self.recommendBusy = false
            await self.polish(outcome.picks, generation: generation)
        }
    }

    func recommendGleaning(on day: Date, night: Bool, scope: RecommendScope) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        beginRecommend(scope: scope, requireUser: false, from: start, to: end, slot: .glean) { context, generation in
            let outcome = RecommendEngine.gleaning(
                points: context.points,
                from: context.from,
                to: context.to,
                night: night,
                tide: context.tide,
                areaTitle: context.title
            )
            guard generation == self.recommendGen else { return }
            self.shorePicks = outcome.shore
            self.skinPicks = outcome.skin
            self.gleanMessage = outcome.message
            self.recommendBusy = false
            await self.polish(outcome.shore + outcome.skin, generation: generation)
        }
    }

    private struct RecommendContext {
        var points: [RecommendEngine.PreparedPoint]
        var tide: TideReport
        var title: String
        var from: Date
        var to: Date
    }

    private enum RecommendMessageSlot {
        case plan
        case now
        case glean
    }

    private func beginRecommend(
        scope: RecommendScope,
        requireUser: Bool,
        from: Date,
        to: Date,
        slot: RecommendMessageSlot,
        work: @escaping (RecommendContext, Int) async -> Void
    ) {
        recommendGen += 1
        let generation = recommendGen
        recommendBusy = true
        writeRecommendMessage("주변 자리와 물때, 수온을 계산하는 중", slot: slot)
        Task {
            let loaded = await self.loadRecommendContext(scope: scope, requireUser: requireUser, from: from, to: to)
            guard generation == self.recommendGen else { return }
            switch loaded {
            case .failure(let error):
                self.recommendBusy = false
                self.writeRecommendMessage(error.message, slot: slot)
            case .success(let context):
                await work(context, generation)
            }
        }
    }

    private func writeRecommendMessage(_ message: String, slot: RecommendMessageSlot) {
        switch slot {
        case .plan: planMessage = message
        case .now: nowMessage = message
        case .glean: gleanMessage = message
        }
    }

    /// 추천 자료를 못 가져왔을 때의 안내 문장. Result의 실패 값은 Error여야 해서 문자열을 그대로 쓰지 않습니다.
    private struct RecommendMessageError: Error {
        let message: String
    }

    private func loadRecommendContext(
        scope: RecommendScope,
        requireUser: Bool,
        from: Date,
        to: Date
    ) async -> Result<RecommendContext, RecommendMessageError> {
        guard let center = recommendCenter(scope: scope, requireUser: requireUser) else {
            if requireUser || scope == .here {
                return .failure(RecommendMessageError(message: "현재 위치가 없습니다. 위치 권한을 허용해 주세요. 다른 지역으로 대신 찾지 않습니다."))
            }
            return .failure(RecommendMessageError(message: "저장된 지역이 없습니다. 지도에서 지역을 맞춘 뒤 이 지역 저장을 누르세요."))
        }
        let found = await candidatePoints(latitude: center.lat, longitude: center.lon, radiusKm: center.radius)
        guard let pack = try? await cachedConditions(latitude: center.lat, longitude: center.lon) else {
            return .failure(RecommendMessageError(message: "날씨와 바다 정보를 가져오지 못했습니다. 인터넷을 확인한 뒤 다시 누르세요."))
        }
        var prepared: [RecommendEngine.PreparedPoint] = []
        for point in found {
            let away = Geo.kilometers(center.lat, center.lon, point.latitude, point.longitude)
            let pointPack: ConditionPack
            if away > 12 {
                pointPack = (try? await cachedConditions(latitude: point.latitude, longitude: point.longitude)) ?? pack
            } else {
                pointPack = pack
            }
            let travel = travelDistance(to: point, centerLat: center.lat, centerLon: center.lon)
            prepared.append(RecommendEngine.PreparedPoint(
                point: point,
                pack: pointPack,
                distanceKm: travel.km,
                distanceFromUser: travel.fromUser
            ))
        }
        let tide = await PublicTideClient.forecast(
            latitude: center.lat,
            longitude: center.lon,
            from: from,
            to: to,
            apiKey: dataGoKrKey
        )
        return .success(RecommendContext(points: prepared, tide: tide, title: center.title, from: from, to: to))
    }

    private func recommendCenter(scope: RecommendScope, requireUser: Bool) -> (lat: Double, lon: Double, radius: Double, title: String)? {
        if requireUser || scope == .here {
            guard let userLat, let userLon else { return nil }
            return (userLat, userLon, radiusKm, "내 위치 반경 \(Int(radiusKm))km")
        }
        guard let region else { return nil }
        return (region.latitude, region.longitude, region.radiusKm, "저장 지역 \(region.name) 반경 \(Int(region.radiusKm))km")
    }

    private func candidatePoints(latitude: Double, longitude: Double, radiusKm: Double) async -> [FishingPoint] {
        let found = (try? await NearbyFinder.search(latitude: latitude, longitude: longitude, radiusKm: radiusKm)) ?? []
        var points = found.filter { Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude) <= radiusKm + 0.3 }
        for mine in myPoints where Geo.kilometers(latitude, longitude, mine.latitude, mine.longitude) <= radiusKm + 0.3 {
            if !points.contains(where: { $0.id == mine.id }) { points.append(mine) }
        }
        if let tapped, Geo.kilometers(latitude, longitude, tapped.latitude, tapped.longitude) <= radiusKm + 0.3,
           !points.contains(where: { $0.id == tapped.id }) {
            points.append(tapped)
        }
        return points
    }

    private func travelDistance(to point: FishingPoint, centerLat: Double, centerLon: Double) -> (km: Double, fromUser: Bool) {
        if let userLat, let userLon {
            return (Geo.kilometers(userLat, userLon, point.latitude, point.longitude), true)
        }
        return (Geo.kilometers(centerLat, centerLon, point.latitude, point.longitude), false)
    }

    private func polish(_ picks: [SpotPick], generation: Int) async {
        guard generation == recommendGen, !geminiKey.isEmpty else { return }
        let blocks = picks.prefix(12).map { (id: $0.id, text: $0.factScript) }
        guard let rewritten = try? await BriefingClient.polishFacts(blocks, apiKey: geminiKey) else { return }
        guard generation == recommendGen else { return }
        func fill(_ items: inout [SpotPick]) {
            for index in items.indices {
                if let text = rewritten[items[index].id] {
                    items[index].aiReason = text
                }
            }
        }
        fill(&planPicks)
        fill(&nowPicks)
        fill(&shorePicks)
        fill(&skinPicks)
    }

    private func analyze(center: ConditionPack, latitude: Double, longitude: Double, generation: Int) async {
        var points = nearby.filter { Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude) <= radiusKm + 0.3 }
        for mine in myPoints where !points.contains(where: { $0.id == mine.id }) {
            points.append(mine)
        }
        if let tapped, !points.contains(where: { $0.id == tapped.id }) {
            points.append(tapped)
        }
        let moon = MoonClock.info(on: Date(), longitude: longitude)
        var next: [String: PointBriefing] = [:]
        for point in points {
            if generation != refreshGen { return }
            let away = Geo.kilometers(latitude, longitude, point.latitude, point.longitude)
            let pack: ConditionPack
            if away > 12 {
                pack = (try? await cachedConditions(latitude: point.latitude, longitude: point.longitude)) ?? center
            } else {
                pack = center
            }
            next[point.id] = FishingAnalyst.brief(
                point: point,
                conditions: pack,
                moon: moon,
                preferred: preferSpecies,
                distanceKm: distance(from: point)
            )
        }
        guard generation == refreshGen else { return }
        briefings = next
        if let selectedPointId, next[selectedPointId] != nil {
            await polish(id: selectedPointId, generation: generation)
        } else if geminiKey.isEmpty == false, let top = next.values.max(by: { $0.score < $1.score }) {
            await polish(id: top.point.id, generation: generation)
        }
    }

    private func polish(id: String, generation: Int) async {
        guard generation == refreshGen, !geminiKey.isEmpty, var briefing = briefings[id], briefing.aiScript == nil else { return }
        guard let text = try? await BriefingClient.rewrite(script: briefing.script, apiKey: geminiKey) else { return }
        guard generation == refreshGen, briefings[id] != nil else { return }
        briefing.aiScript = text
        briefings[id] = briefing
    }

    private func cachedConditions(latitude: Double, longitude: Double) async throws -> ConditionPack {
        let key = String(format: "%.2f,%.2f", latitude, longitude)
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < 30 * 60 {
            return cached
        }
        let pack = try await ConditionClient.fetch(latitude: latitude, longitude: longitude)
        cache[key] = pack
        return pack
    }

    private func distance(from point: FishingPoint) -> Double {
        if useMyLocation, let userLat, let userLon {
            return Geo.kilometers(userLat, userLon, point.latitude, point.longitude)
        }
        return Geo.kilometers(centerLat, centerLon, point.latitude, point.longitude)
    }

    private var diskURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("바로낚시", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("[바로낚시]_자료.json")
    }

    private func loadDisk() {
        guard let data = try? Data(contentsOf: diskURL),
              let box = try? JSONDecoder().decode(DiskBox.self, from: data) else { return }
        myPoints = box.myPoints
        region = box.region
        radiusKm = box.radiusKm
        preferSpecies = box.preferSpecies
        useMyLocation = box.useMyLocation
        if let lastLat = box.lastLat, let lastLon = box.lastLon {
            centerLat = lastLat
            centerLon = lastLon
        }
    }

    private func saveDisk() {
        let box = DiskBox(
            myPoints: myPoints,
            region: region,
            radiusKm: radiusKm,
            preferSpecies: preferSpecies,
            useMyLocation: useMyLocation,
            lastLat: centerLat,
            lastLon: centerLon
        )
        guard let data = try? JSONEncoder().encode(box) else { return }
        try? data.write(to: diskURL, options: .atomic)
    }
}
