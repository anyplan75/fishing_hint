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

struct LinkLine: Equatable {
    var connected: Bool
    var reason: String
    var word: String { connected ? "연결됨" : "없음" }

    static func absent(_ reason: String) -> LinkLine {
        LinkLine(connected: false, reason: reason)
    }

    static let connected = LinkLine(connected: true, reason: "")
}

@MainActor
final class AppStore: ObservableObject {
    @Published var mapboxToken = ""
    @Published var geminiKey = ""
    /// 지도 반경입니다. 저장한 값이 없으면 5km에서 시작하고, 고른 값은 남깁니다.
    @Published var radiusKm = 5.0
    @Published var useMyLocation = true
    @Published var preferSpecies: [String] = []
    @Published var region: SavedRegion?
    @Published var myPoints: [FishingPoint] = []
    @Published var nearby: [FishingPoint] = []
    @Published var tapped: FishingPoint?
    /// 이름을 적어 내 포인트로 저장할 자리입니다. 비우면 저장하지 않습니다.
    @Published var savePrompt: SavePrompt?
    @Published var briefings: [String: PointBriefing] = [:]
    /// 자리를 열었는데 물때·수온을 못 받으면 계산 중 대신 이 짧은 이유를 보여 줍니다.
    @Published var detailMiss: [String: String] = [:]
    @Published var selectedPointId: String?
    private var briefGen: [String: Int] = [:]
    @Published var centerLat = 37.45
    @Published var centerLon = 126.59
    @Published var userLat: Double?
    @Published var userLon: Double?
    @Published var locationText = "위치를 확인하는 중"
    @Published var statusText = "지도를 준비하고 있습니다."
    @Published var busy = false
    @Published var flyToken = 0
    @Published var searchHits: [PlaceNameClient.Hit] = []
    /// 흔들리는 현재 위치를 가까운 길에 붙였는지 짧은 안내입니다.
    @Published var roadNote = ""
    /// 현재 위치에서 고른 자리까지 그린 길과 짧은 안내입니다.
    @Published var routeNote = ""
    @Published var routeLine: [[Double]] = []
    @Published var mapFit = 0
    @Published var destination: PlaceNameClient.Hit?
    @Published var selectedSearchId: String?
    @Published var regionTitle = "선택한 지역"
    @Published var dataGoKrKey = ""
    /// 바다해도만 씁니다. 조석예보 키와 섞지 않습니다.
    @Published var haereumKey = ""
    /// 유튜브 공개 영상 검색만 씁니다. 로그인이나 비공개 영상은 보지 않습니다.
    @Published var youtubeKey = ""
    /// 바다낚시지수 조회만 씁니다. 조석예보 키와 다릅니다.
    @Published var fishingIndexKey = ""
    /// 네이버 공식 검색만 씁니다. 없으면 화면에는 필요한 키 이름만 적습니다.
    @Published var naverClientId = ""
    @Published var naverClientSecret = ""
    /// 구글 검색 제안 HTML입니다. 결과 카드 위에 그대로 보여 줍니다.
    @Published var googleSuggestHtml = ""
    @Published var planPicks: [SpotPick] = []
    @Published var nowPicks: [SpotPick] = []
    @Published var shorePicks: [SpotPick] = []
    @Published var skinPicks: [SpotPick] = []
    @Published var planMessage = "지도에 찍은 자리, 핀이 없으면 현재 위치를 중심으로 고른 반경 안만 읽어 최대 10곳을 줄 세웁니다."
    @Published var nowMessage = "지도에 찍은 자리, 핀이 없으면 현재 위치를 중심으로 고른 반경 안만 읽어 최대 3곳을 줄 세웁니다."
    @Published var gleanMessage = "해루질은 낚시 추천과 따로 봅니다. 수중은 스킨스쿠버지수 포인트만 봅니다."
    @Published var recommendBusy = false
    @Published var selectedPickId: String?
    @Published var mapLink = LinkLine.absent("지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
    @Published var aiLink = LinkLine.absent("인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
    @Published var tideLink = LinkLine.absent("조석 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.")
    @Published var youtubeLink = LinkLine.absent("유튜브 없음. 비밀 파일에 YOUTUBE_API_KEY 가 없습니다.")
    @Published var fishingIndexLink = LinkLine.absent("바다낚시지수 없음. 비밀 파일에 DATA_GO_KR_FISHING_INDEX_KEY 가 없습니다.")
    @Published var fishingSpotLink = LinkLine.absent("전국낚시터 없음. 아직 표준데이터를 부르지 않았습니다.")
    @Published var scubaLink = LinkLine.absent("스킨스쿠버지수 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.")
    @Published var naverLink = LinkLine.absent("네이버 검색 없음. 비밀 파일에 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 이 필요합니다.")
    @Published var googleLink = LinkLine.absent("구글 검색 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
    @Published var savedTimes: [String: SavedSpotTimes] = [:]
    @Published var savedTimesNote = "저장한 자리의 낚시 시간과 해루질 시간을 받은 예보로 계산합니다."

    private let locator = LocationFixer()
    private var cache: [String: ConditionPack] = [:]
    private var refreshGen = 0
    private var recommendGen = 0
    private var savedPlanGen = 0
    private var didFirstFix = false
    private var roadGen = 0
    private var routeGen = 0
    private var rawTrack: [(longitude: Double, latitude: Double)] = []

    var ranked: [PointBriefing] {
        briefings.values.sorted { left, right in
            if left.score == right.score {
                return (left.distanceKm ?? 999) < (right.distanceKm ?? 999)
            }
            return left.score > right.score
        }
    }

    /// 반경 원의 중심입니다. 지도를 찍어 둔 자리가 있으면 그 지점이고, 핀이 없으면 현재 위치입니다.
    var circleAnchor: (latitude: Double, longitude: Double)? {
        if let tapped {
            return (tapped.latitude, tapped.longitude)
        }
        guard let userLat, let userLon else { return nil }
        return (userLat, userLon)
    }

    /// 고른 반경 원 안인지 봅니다. 중심이 없으면 원 안이 아닙니다.
    func isInsideCircle(latitude: Double, longitude: Double) -> Bool {
        guard let anchor = circleAnchor else { return false }
        return Geo.kilometers(anchor.latitude, anchor.longitude, latitude, longitude) <= radiusKm
    }

    func start() {
        loadDisk()
        let secrets = SecretVault.load()
        mapboxToken = secrets.mapbox
        geminiKey = secrets.gemini
        dataGoKrKey = secrets.dataGoKr
        haereumKey = secrets.haereum
        youtubeKey = secrets.youtube
        fishingIndexKey = secrets.fishingIndex
        naverClientId = secrets.naverClientId
        naverClientSecret = secrets.naverClientSecret
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
        resetLinksForKeys()
        refreshSavedPlans()
    }

    func applyFix(_ coordinate: CLLocationCoordinate2D) {
        let moved: Double
        if let last = rawTrack.last {
            moved = Geo.kilometers(last.latitude, last.longitude, coordinate.latitude, coordinate.longitude)
        } else {
            moved = 999
        }
        guard moved >= 0.03 || rawTrack.isEmpty else { return }
        rawTrack.append((longitude: coordinate.longitude, latitude: coordinate.latitude))
        if rawTrack.count > 8 { rawTrack.removeFirst(rawTrack.count - 8) }
        userLat = coordinate.latitude
        userLon = coordinate.longitude
        locationText = "현재 위치를 사용 중"
        snapRoad()
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
            locationText = userLat == nil ? "현재 위치를 가져오는 중" : "현재 위치를 사용 중"
        case .denied, .restricted:
            locationText = "위치 권한이 꺼져 있습니다"
            statusText = "지도를 찍어 중심을 정하거나, 위치 권한을 허용하세요."
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
        guard let anchor = circleAnchor else {
            statusText = "중심이 없습니다. 지도를 찍거나 위치 권한을 허용하세요."
            return
        }
        refreshGen += 1
        let gen = refreshGen
        let lat = anchor.latitude
        let lon = anchor.longitude
        let radius = radiusKm
        busy = true
        statusText = "주변 자리와 물때, 수온을 계산하는 중"
        Task {
            async let foundCall = NearbyFinder.search(latitude: lat, longitude: lon, radiusKm: radius)
            async let packCall = cachedConditions(latitude: lat, longitude: lon)
            async let nameCall = PlaceNameClient.reverse(latitude: lat, longitude: lon, token: mapboxToken)
            async let tideCall: Void = noteTide(latitude: lat, longitude: lon, generation: gen)
            var found: [FishingPoint] = []
            do {
                found = try await foundCall
            } catch {
                found = []
            }
            let pack = try? await packCall
            let named = await nameCall
            await tideCall
            guard gen == self.refreshGen else { return }
            noteMapbox(named.reach)
            if let title = named.name, !title.isEmpty { regionTitle = title }
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
                statusText = "이 반경의 공개 자리가 없습니다. 지도를 누르면 자리만 남고, 분석을 누르면 계산합니다."
            } else {
                statusText = "\(ranked.count)곳을 조건 점수로 줄 세웠습니다."
            }
            saveDisk()
        }
    }

    /// 지도를 누르면 저장하지 않은 자리 하나만 남깁니다. 물때와 날씨는 분석을 누를 때 계산합니다.
    func dropSpot(latitude: Double, longitude: Double) {
        let point = FishingPoint(
            id: String(format: "tap-%.4f-%.4f", latitude, longitude),
            name: "찍은 자리",
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
        clearUnsavedTap()
        tapped = point
        savePrompt = SavePrompt(point: point)
        statusText = "자리 이름을 적고 저장하세요. 이름을 비우면 저장하지 않습니다."
    }

    func askSaveName(for point: FishingPoint) {
        savePrompt = SavePrompt(point: point)
    }

    /// 이름이 있을 때만 내 포인트에 넣습니다. 비어 있으면 저장하지 않습니다.
    @discardableResult
    func commitNamedSave(point: FishingPoint, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "이름을 비우면 저장하지 않습니다."
            return false
        }
        var named = point
        named.name = trimmed
        saveMine(from: named)
        savePrompt = nil
        statusText = "\(trimmed) 을 내 포인트에 저장했습니다."
        return true
    }

    private func clearUnsavedTap() {
        let stale = briefings.filter { id, briefing in
            briefing.point.source == "찍은자리" && !myPoints.contains(where: { $0.id == id })
        }
        for id in stale.keys {
            briefings.removeValue(forKey: id)
            if selectedPointId == id { selectedPointId = nil }
        }
        if let old = tapped, old.source == "찍은자리", !myPoints.contains(where: { $0.id == old.id }) {
            briefings.removeValue(forKey: old.id)
            if selectedPointId == old.id { selectedPointId = nil }
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        routeLine = []
        routeNote = ""
        destination = nil
        selectedSearchId = nil
        let latitude = userLat ?? centerLat
        let longitude = userLon ?? centerLon
        Task {
            let found = await MapboxGuide.search(
                query: trimmed,
                latitude: latitude,
                longitude: longitude,
                token: mapboxToken
            )
            noteMapbox(found.reach)
            searchHits = found.hits
            if found.hits.isEmpty {
                statusText = found.note
                return
            }
            let restaurants = found.hits.filter { $0.kind == .restaurant }.count
            let lodgings = found.hits.filter { $0.kind == .lodging }.count
            if restaurants > 0 && lodgings == 0 {
                statusText = "식당 \(restaurants)곳을 핀으로 표시했습니다."
            } else if lodgings > 0 && restaurants == 0 {
                statusText = "숙소 \(lodgings)곳을 핀으로 표시했습니다."
            } else {
                statusText = "\(found.hits.count)곳을 지도 핀으로 표시했습니다."
            }
            mapFit += 1
        }
    }

    /// 핀을 누르면 상세 화면은 열지 않습니다. 이름과 길만 고르고, 상세는 분석 카드를 누를 때 엽니다.
    func inspect(_ id: String) {
        if id.hasPrefix("search-") {
            openSearch(id)
            return
        }
        if tapped?.id == id, tapped?.source == "찍은자리", briefings[id] == nil {
            askSaveName(for: tapped!)
            guide(to: PlaceNameClient.Hit(id: tapped!.id, name: tapped!.name, latitude: tapped!.latitude, longitude: tapped!.longitude))
            return
        }
        if let briefing = briefings[id] {
            regionTitle = briefing.point.name
            guide(to: PlaceNameClient.Hit(
                id: briefing.point.id,
                name: briefing.point.name,
                latitude: briefing.point.latitude,
                longitude: briefing.point.longitude
            ))
            return
        }
        let point = myPoints.first { $0.id == id } ?? (tapped?.id == id ? tapped : nil)
        guard let point else { return }
        regionTitle = point.name
        guide(to: PlaceNameClient.Hit(id: point.id, name: point.name, latitude: point.latitude, longitude: point.longitude))
    }

    func openSearch(_ pinId: String) {
        let key = pinId.hasPrefix("search-") ? String(pinId.dropFirst("search-".count)) : pinId
        guard let hit = searchHits.first(where: { $0.id == key }) else { return }
        selectedSearchId = hit.id
        go(to: hit)
    }

    func go(to hit: PlaceNameClient.Hit) {
        centerLat = hit.latitude
        centerLon = hit.longitude
        regionTitle = hit.title
        useMyLocation = false
        destination = hit
        selectedSearchId = hit.id
        flyToken += 1
        saveDisk()
        guide(to: hit)
        refresh()
    }

    /// 출발은 현재 위치, 도착은 고른 자리나 검색 결과입니다.
    func guideChosen() {
        if let id = selectedSearchId, let hit = searchHits.first(where: { $0.id == id }) {
            guide(to: hit)
            return
        }
        if let destination {
            guide(to: destination)
            return
        }
        guard let point = chosenPoint() else {
            routeLine = []
            routeNote = "도착 자리를 고르거나 검색하세요."
            return
        }
        guide(to: PlaceNameClient.Hit(id: point.id, name: point.name, latitude: point.latitude, longitude: point.longitude))
    }

    func guide(to hit: PlaceNameClient.Hit) {
        destination = hit
        routeGen += 1
        let generation = routeGen
        guard let userLat, let userLon else {
            routeLine = []
            routeNote = "현재 위치가 없어 길을 계산하지 못했습니다."
            mapFit += 1
            return
        }
        routeNote = "길을 계산하는 중"
        let token = mapboxToken
        let name = hit.title
        Task {
            let drawn = await MapboxGuide.route(
                fromLon: userLon,
                fromLat: userLat,
                toLon: hit.longitude,
                toLat: hit.latitude,
                name: name,
                token: token
            )
            guard generation == self.routeGen else { return }
            routeLine = drawn.line
            routeNote = drawn.note
            mapFit += 1
        }
    }

    func select(_ id: String) {
        if tapped?.id == id, tapped?.source == "찍은자리", briefings[id] == nil {
            askSaveName(for: tapped!)
            guide(to: PlaceNameClient.Hit(id: tapped!.id, name: tapped!.name, latitude: tapped!.latitude, longitude: tapped!.longitude))
            return
        }
        selectedPointId = id
        if let briefing = briefings[id] {
            guide(to: PlaceNameClient.Hit(id: briefing.point.id, name: briefing.point.name, latitude: briefing.point.latitude, longitude: briefing.point.longitude))
            Task { await polish(id: id, generation: refreshGen) }
            return
        }
        let point = myPoints.first { $0.id == id } ?? (tapped?.id == id ? tapped : nil)
        guard let point else {
            detailMiss[id] = "이 자리를 찾지 못했습니다."
            return
        }
        guide(to: PlaceNameClient.Hit(id: point.id, name: point.name, latitude: point.latitude, longitude: point.longitude))
        fillBriefing(for: point)
    }

    /// 저장한 자리의 물때와 수온을 받아 화면에 올립니다. 못 받으면 계산 중을 끝냅니다.
    private func fillBriefing(for point: FishingPoint) {
        let generation = (briefGen[point.id] ?? 0) + 1
        briefGen[point.id] = generation
        detailMiss[point.id] = nil
        Task {
            let outcome = await self.packWithinLimit(latitude: point.latitude, longitude: point.longitude)
            guard self.briefGen[point.id] == generation else { return }
            guard let pack = outcome.pack else {
                guard self.briefings[point.id] == nil else { return }
                self.detailMiss[point.id] = outcome.reason
                return
            }
            guard !pack.hours.isEmpty else {
                self.detailMiss[point.id] = "물때와 수온을 가져오지 못했습니다."
                return
            }
            let moon = MoonClock.info(on: Date(), longitude: point.longitude)
            var briefing = FishingAnalyst.brief(
                point: point,
                conditions: pack,
                moon: moon,
                preferred: self.preferSpecies,
                distanceKm: self.distance(from: point)
            )
            self.briefings[point.id] = briefing
            self.detailMiss[point.id] = nil
            if let text = await self.rewriteBrief(briefing.script) {
                guard self.briefGen[point.id] == generation else { return }
                briefing.aiScript = text
                self.briefings[point.id] = briefing
            }
        }
    }

    private func packWithinLimit(latitude: Double, longitude: Double) async -> (pack: ConditionPack?, reason: String) {
        await withTaskGroup(of: (ConditionPack?, String).self) { group in
            group.addTask {
                do {
                    return (try await self.cachedConditions(latitude: latitude, longitude: longitude), "")
                } catch {
                    return (nil, "물때와 수온을 가져오지 못했습니다.")
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 32_000_000_000)
                } catch {
                    return (nil, "")
                }
                return (nil, "물때와 수온을 시간 안에 받지 못했습니다.")
            }
            let first = await group.next() ?? (nil, "물때와 수온을 가져오지 못했습니다.")
            group.cancelAll()
            if first.0 == nil, first.1.isEmpty {
                return (nil, "물때와 수온을 가져오지 못했습니다.")
            }
            return first
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
            detailMiss[copy.id] = nil
        }
        detailMiss.removeValue(forKey: point.id)
        selectedPointId = copy.id
        if tapped?.id == point.id { tapped = copy }
        saveDisk()
        refreshSavedPlans()
        if briefings[copy.id] == nil {
            fillBriefing(for: copy)
        }
    }

    func updateMine(_ point: FishingPoint) {
        let trimmed = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "이름을 비우면 저장하지 않습니다."
            return
        }
        var named = point
        named.name = trimmed
        guard let index = myPoints.firstIndex(where: { $0.id == named.id }) else { return }
        myPoints[index] = named
        saveDisk()
        statusText = "\(named.name) 을 내 포인트에 저장했습니다."
        fillBriefing(for: named)
        refreshSavedPlans()
    }

    func deleteMine(_ point: FishingPoint) {
        myPoints.removeAll { $0.id == point.id }
        briefings.removeValue(forKey: point.id)
        detailMiss.removeValue(forKey: point.id)
        briefGen.removeValue(forKey: point.id)
        if selectedPointId == point.id { selectedPointId = nil }
        if tapped?.id == point.id { tapped = nil }
        savedTimes.removeValue(forKey: point.id)
        saveDisk()
        let removedId = point.id
        Task { await GleanAlarm.cancel(pointId: removedId) }
        refreshSavedPlans()
    }

    func keepRadius() {
        saveDisk()
    }

    func toggleSpecies(_ name: String) {
        if let index = preferSpecies.firstIndex(of: name) {
            preferSpecies.remove(at: index)
        } else {
            preferSpecies.append(name)
        }
        saveDisk()
        refresh()
        refreshSavedPlans()
    }

    /// 저장한 자리만 봅니다. 찍기만 한 자리는 낚시 시간 추천과 해루질 알림에 넣지 않습니다.
    func refreshSavedPlans() {
        savedPlanGen += 1
        let generation = savedPlanGen
        let points = myPoints.filter(\.isMine)
        if points.isEmpty {
            savedTimes = [:]
            savedTimesNote = "저장한 자리가 없습니다. 저장하지 않은 자리는 시간 추천과 알림 대상이 아닙니다."
            Task {
                guard generation == self.savedPlanGen else { return }
                _ = await GleanAlarm.replace(items: [])
            }
            return
        }
        savedTimesNote = "등록한 자리의 물때와 날씨를 보는 중"
        let species = preferSpecies
        let apiKey = dataGoKrKey
        Task {
            var next: [String: SavedSpotTimes] = [:]
            var alarms: [(point: FishingPoint, day: [Date], night: [Date])] = []
            let from = Date()
            let to = from.addingTimeInterval(48 * 3600)
            for point in points {
                if generation != self.savedPlanGen { return }
                await self.attachIndex(to: point)
                guard let pack = try? await self.cachedConditions(latitude: point.latitude, longitude: point.longitude) else {
                    next[point.id] = SavedSpotTimes(
                        pointId: point.id,
                        fishingLines: ["날씨와 바다 정보를 가져오지 못했습니다. 시간을 만들지 않았습니다."],
                        dayLines: ["날씨와 바다 정보를 가져오지 못했습니다."],
                        nightLines: ["날씨와 바다 정보를 가져오지 못했습니다."],
                        successText: "성공률은 날씨를 받지 못해 계산하지 못했습니다.",
                        indexLine: OfficialNotes.caption(pointId: point.id, species: "", when: Date())
                    )
                    continue
                }
                let tide = await PublicTideClient.forecast(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    from: from,
                    to: to,
                    apiKey: apiKey
                )
                if generation != self.savedPlanGen { return }
                let visit = RecommendEngine.savedVisit(point: point, pack: pack, tide: tide, preferred: species)
                let fishingLines = visit.fishing.isEmpty
                    ? ["받은 예보 안에서 낚시하기 좋은 시간이 없습니다."]
                    : visit.fishing.map {
                        "\(FieldFormat.dayClock($0.when)) · 성공률 \($0.successRate)% · \($0.indexLine) · \($0.species). 받은 물때·날씨로 고른 시간입니다. 알림은 보내지 않습니다."
                    }
                let dayPicks = [visit.dayShore, visit.daySkin].compactMap { $0 }
                let nightPicks = [visit.nightShore, visit.nightSkin].compactMap { $0 }
                let dayLines = dayPicks.isEmpty
                    ? ["받은 예보 안에서 주간 해루질에 맞는 시간이 없습니다."]
                    : dayPicks.map { self.gleanLine($0) }
                let nightLines = nightPicks.isEmpty
                    ? ["받은 예보 안에서 야간 해루질에 맞는 시간이 없습니다."]
                    : nightPicks.map { self.gleanLine($0) }
                let best = visit.fishing.max { $0.successRate < $1.successRate }
                next[point.id] = SavedSpotTimes(
                    pointId: point.id,
                    fishingLines: fishingLines,
                    dayLines: dayLines,
                    nightLines: nightLines,
                    successText: best.map { "성공률 \($0.successRate)%" } ?? "성공률은 받은 예보 안에서 고르지 못했습니다.",
                    indexLine: best?.indexLine ?? OfficialNotes.caption(pointId: point.id, species: "", when: Date())
                )
                alarms.append((point: point, day: dayPicks.map(\.when), night: nightPicks.map(\.when)))
            }
            guard generation == self.savedPlanGen else { return }
            self.savedTimes = next
            let note = await GleanAlarm.replace(items: alarms)
            guard generation == self.savedPlanGen else { return }
            self.savedTimesNote = note
        }
    }

    private func gleanLine(_ pick: SpotPick) -> String {
        let place = pick.kind == .skin ? "수중" : "갯가"
        return "\(FieldFormat.dayClock(pick.when)) · \(place) · 성공률 \(pick.successRate)% · \(pick.indexLine) · \(pick.species). 받은 물때·날씨로 고른 시간입니다."
    }

    /// 저장한 자리 근처의 공식 바다낚시지수만 붙입니다. 없으면 지수 없음으로 둡니다.
    private func attachIndex(to point: FishingPoint) async {
        let load = await SeaFishingIndexClient.load(
            latitude: point.latitude,
            longitude: point.longitude,
            radiusKm: 15,
            apiKey: fishingIndexKey
        )
        noteFishingIndex(load)
        OfficialNotes.rows.removeValue(forKey: point.id)
        if !load.connected {
            OfficialNotes.rows[point.id] = [
                OfficialIndexRow(day: "", half: "", species: "", line: load.note, rank: 0)
            ]
            return
        }
        SeaFishingIndexClient.attach(to: [point], anchors: load.points)
    }

    func pick(id: String) -> SpotPick? {
        planPicks.first { $0.id == id }
            ?? nowPicks.first { $0.id == id }
            ?? shorePicks.first { $0.id == id }
            ?? skinPicks.first { $0.id == id }
    }

    func recommendPlan(on day: Date, startHour: Int, endHour: Int, scope: RecommendScope) {
        let span = RecommendEngine.window(on: day, startHour: startHour, endHour: endHour)
        beginRecommend(scope: scope, requireUser: false, from: span.start, to: span.end, slot: .plan, mentions: true) { context, generation in
            let outcome = RecommendEngine.fishing(
                points: context.points,
                from: context.from,
                to: context.to,
                limit: 10,
                preferred: self.preferSpecies,
                tide: context.tide,
                areaTitle: context.title,
                kind: .plan,
                lookedAround: context.lookedAround,
                intro: context.intro,
                keepDangerous: true
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
        beginRecommend(scope: .here, requireUser: true, from: start, to: end, slot: .now, mentions: true) { context, generation in
            let outcome = RecommendEngine.fishing(
                points: context.points,
                from: context.from,
                to: context.to,
                limit: 3,
                preferred: self.preferSpecies,
                tide: context.tide,
                areaTitle: context.title,
                kind: .now,
                lookedAround: context.lookedAround,
                intro: context.intro,
                keepDangerous: true
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
            var skinPrepared: [RecommendEngine.PreparedPoint] = []
            var skinNote = "스킨스쿠버지수 없음. 기준점을 확인하지 못했습니다."
            if let center = self.recommendCenter(scope: scope, requireUser: false) {
                let skin = await SkinScubaClient.load(
                    latitude: center.lat,
                    longitude: center.lon,
                    radiusKm: center.radius,
                    apiKey: self.dataGoKrKey,
                    night: night
                )
                self.noteScuba(skin)
                skinNote = skin.note
                if let pack = try? await self.cachedConditions(latitude: center.lat, longitude: center.lon) {
                    for place in skin.places {
                        OfficialNotes.rows[place.point.id] = place.hours.map {
                            OfficialIndexRow(day: "", half: $0.half, species: "", line: $0.line, rank: $0.rank)
                        }
                        let away = Geo.kilometers(center.lat, center.lon, place.point.latitude, place.point.longitude)
                        let pointPack = away > 12
                            ? ((try? await self.cachedConditions(latitude: place.point.latitude, longitude: place.point.longitude)) ?? pack)
                            : pack
                        let travel = self.travelDistance(to: place.point, centerLat: center.lat, centerLon: center.lon)
                        skinPrepared.append(RecommendEngine.PreparedPoint(
                            point: place.point,
                            pack: pointPack,
                            distanceKm: travel.km,
                            distanceFromUser: travel.fromUser
                        ))
                    }
                }
            }
            let outcome = RecommendEngine.gleaning(
                points: context.points,
                from: context.from,
                to: context.to,
                night: night,
                tide: context.tide,
                areaTitle: context.title,
                lookedAround: context.lookedAround,
                skinOverride: skinPrepared,
                skinNote: skinNote
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
        var lookedAround: Bool
        var intro: String
    }

    private struct MentionMemory {
        var signature: String
        var at: Date
        var points: [FishingPoint]
        var intro: String
        var title: String
        var suggestHtml: String
    }

    private var mentionMemory: MentionMemory?

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
        mentions: Bool = false,
        work: @escaping (RecommendContext, Int) async -> Void
    ) {
        recommendGen += 1
        let generation = recommendGen
        recommendBusy = true
        let waiting = mentions
            ? "공개 글, 유튜브, 바다낚시지수, 전국낚시터, 구글 지명 검색을 읽는 중"
            : "주변 자리, 스킨스쿠버지수, 물때, 수온을 계산하는 중"
        writeRecommendMessage(waiting, slot: slot)
        Task {
            let loaded = mentions
                ? await self.loadMentionedContext(from: from, to: to)
                : await self.loadRecommendContext(scope: scope, requireUser: requireUser, from: from, to: to)
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
            if requireUser {
                return .failure(RecommendMessageError(message: "현재 위치가 없습니다. 위치 권한을 허용해 주세요."))
            }
            if scope == .here {
                return .failure(RecommendMessageError(message: "현재 위치가 없습니다. 위치 권한을 허용해 주세요."))
            }
            return .failure(RecommendMessageError(message: "저장된 지역이 없습니다. 지도에서 지역을 맞춘 뒤 이 지역 저장을 누르세요."))
        }
        let pool = await candidatePoints(latitude: center.lat, longitude: center.lon, radiusKm: center.radius)
        let found = pool.points
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
        noteTideReport(tide)
        return .success(RecommendContext(points: prepared, tide: tide, title: center.title, from: from, to: to, lookedAround: pool.lookedAround, intro: ""))
    }

    /// 낚시 계획과 바로가자만 씁니다. 미리 등록된 목록을 그대로 줄 세우지 않습니다.
    private func loadMentionedContext(
        from: Date,
        to: Date
    ) async -> Result<RecommendContext, RecommendMessageError> {
        guard let center = circleCenter() else {
            return .failure(RecommendMessageError(message: "중심이 없습니다. 지도에서 자리를 찍거나 위치 권한을 허용해 주세요."))
        }
        let signature = String(format: "%.3f,%.3f,%.0f", center.lat, center.lon, center.radius)
        let remembered = mentionMemory
        let cachedInside = remembered?.signature == signature
            ? (remembered?.points.filter { Geo.kilometers(center.lat, center.lon, $0.latitude, $0.longitude) <= center.radius } ?? [])
            : []
        let located: [FishingPoint]
        let intro: String
        let title: String
        if let remembered, remembered.signature == signature, !cachedInside.isEmpty {
            located = cachedInside
            intro = remembered.intro
            title = remembered.title
            googleSuggestHtml = remembered.suggestHtml
        } else {
            async let noteCall = PublicFishingClient.load()
            async let nameCall = PlaceNameClient.areaLabels(latitude: center.lat, longitude: center.lon, token: mapboxToken)
            let bundle = await noteCall
            let labels = await nameCall
            let anchorName = labels.first { PublicNearby.canFilter($0) } ?? labels.first ?? center.title
            let notes = PublicNearby.keep(bundle.notes, anchor: labels.joined(separator: " "))
            let region = labels.filter { PublicNearby.canFilter($0) }.min { $0.count < $1.count } ?? anchorName
            let videos = await YouTubePublicClient.search(region: region, apiKey: youtubeKey)
            noteYouTube(fetched: !videos.isEmpty)
            let reading = Array(notes.prefix(16)) + videos
            OfficialNotes.reset()
            async let indexCall = SeaFishingIndexClient.load(
                latitude: center.lat,
                longitude: center.lon,
                radiusKm: center.radius,
                apiKey: fishingIndexKey
            )
            async let spotCall = FishingSpotStandardClient.load(
                latitude: center.lat,
                longitude: center.lon,
                radiusKm: center.radius
            )
            let outcome = await MentionFinder.find(
                anchorName: anchorName,
                latitude: center.lat,
                longitude: center.lon,
                radiusKm: center.radius,
                notes: reading,
                known: [],
                mapboxToken: mapboxToken,
                geminiKey: geminiKey
            )
            let index = await indexCall
            let spots = await spotCall
            let web = await PlaceWebSearch.load(
                latitude: center.lat,
                longitude: center.lon,
                radiusKm: center.radius,
                mapboxToken: mapboxToken,
                naverId: naverClientId,
                naverSecret: naverClientSecret,
                geminiKey: geminiKey
            )
            noteFishingIndex(index)
            noteFishingSpots(spots)
            noteWeb(web)
            if !index.connected {
                OfficialNotes.blocked = index.note
            }
            let merged = outcome.points + index.points + spots.points + web.points
            var kept: [FishingPoint] = []
            for point in merged {
                if Geo.kilometers(center.lat, center.lon, point.latitude, point.longitude) > center.radius {
                    continue
                }
                if kept.contains(where: { Geo.kilometers($0.latitude, $0.longitude, point.latitude, point.longitude) < 0.4 && $0.name == point.name }) {
                    continue
                }
                kept.append(point)
            }
            SeaFishingIndexClient.attach(to: kept, anchors: index.points)
            guard !kept.isEmpty else {
                var reason = [outcome.failure, index.note, spots.note, web.note].compactMap { $0 }.filter { !$0.isEmpty }
                if reason.isEmpty { reason = ["추천할 자리를 정하지 못했습니다. 없는 자리는 만들지 않았습니다."] }
                return .failure(RecommendMessageError(message: reason.joined(separator: " ")))
            }
            located = kept
            let lines = [outcome.points.isEmpty ? (outcome.failure ?? "") : outcome.intro, index.note, spots.note, web.note]
            intro = lines.filter { !$0.isEmpty }.joined(separator: " ")
            title = anchorName
            mentionMemory = MentionMemory(signature: signature, at: Date(), points: located, intro: intro, title: title, suggestHtml: web.suggestHtml)
        }
        guard let pack = try? await cachedConditions(latitude: center.lat, longitude: center.lon) else {
            return .failure(RecommendMessageError(message: "날씨와 바다 정보를 가져오지 못했습니다. 인터넷을 확인한 뒤 다시 누르세요."))
        }
        var prepared: [RecommendEngine.PreparedPoint] = []
        for point in located {
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
        noteTideReport(tide)
        return .success(RecommendContext(
            points: prepared,
            tide: tide,
            title: title,
            from: from,
            to: to,
            lookedAround: true,
            intro: intro
        ))
    }

    private func recommendCenter(scope: RecommendScope, requireUser: Bool) -> (lat: Double, lon: Double, radius: Double, title: String)? {
        if requireUser || scope == .here {
            guard let spot = mapUserSpot() else { return nil }
            return (spot.lat, spot.lon, radiusKm, "내 위치 반경 \(Int(radiusKm))km")
        }
        guard let region else { return nil }
        return (region.latitude, region.longitude, region.radiusKm, "저장 지역 \(region.name) 반경 \(Int(region.radiusKm))km")
    }

    /// 낚시 계획과 바로가자가 지도 원과 같이 쓰는 중심입니다.
    private func circleCenter() -> (lat: Double, lon: Double, radius: Double, title: String)? {
        guard let anchor = circleAnchor else { return nil }
        let who = tapped == nil ? "현재 위치" : "찍은 자리"
        return (anchor.latitude, anchor.longitude, radiusKm, "\(who) 반경 \(Int(radiusKm))km")
    }

    /// 지도가 지금 쓰는 내 위치입니다. 좌표가 없으면 기본 지도 중심을 내 위치처럼 쓰지 않습니다.
    private func mapUserSpot() -> (lat: Double, lon: Double)? {
        guard let userLat, let userLon else { return nil }
        return (userLat, userLon)
    }

    /// 내 위치나 고른 구역 주변을 검색합니다. 실패하면 그 반경의 저장 자리와 찍은 자리만 남기고, 검색한 척하지 않습니다.
    private func candidatePoints(latitude: Double, longitude: Double, radiusKm: Double) async -> (points: [FishingPoint], lookedAround: Bool) {
        let found: [FishingPoint]
        let lookedAround: Bool
        do {
            found = try await NearbyFinder.search(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
            lookedAround = true
        } catch is CancellationError {
            return ([], false)
        } catch {
            found = []
            lookedAround = false
        }
        var points: [FishingPoint] = []
        if lookedAround {
            for point in found { appendCandidate(point, to: &points, latitude: latitude, longitude: longitude, radiusKm: radiusKm) }
        }
        for point in myPoints { appendCandidate(point, to: &points, latitude: latitude, longitude: longitude, radiusKm: radiusKm) }
        if let tapped { appendCandidate(tapped, to: &points, latitude: latitude, longitude: longitude, radiusKm: radiusKm) }
        return (points, lookedAround)
    }

    private func appendCandidate(
        _ point: FishingPoint,
        to points: inout [FishingPoint],
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) {
        guard Geo.kilometers(latitude, longitude, point.latitude, point.longitude) <= radiusKm + 0.3 else { return }
        guard !points.contains(where: { $0.id == point.id }) else { return }
        points.append(point)
    }

    private func travelDistance(to point: FishingPoint, centerLat: Double, centerLon: Double) -> (km: Double, fromUser: Bool) {
        if let userLat, let userLon {
            return (Geo.kilometers(userLat, userLon, point.latitude, point.longitude), true)
        }
        return (Geo.kilometers(centerLat, centerLon, point.latitude, point.longitude), false)
    }

    private func polish(_ picks: [SpotPick], generation: Int) async {
        guard generation == recommendGen else { return }
        let key = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            aiLink = .absent("인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
            return
        }
        guard !picks.isEmpty else { return }
        let blocks = picks.prefix(12).map { (id: $0.id, text: $0.factScript) }
        guard let rewritten = try? await BriefingClient.polishFacts(blocks, apiKey: key) else {
            aiLink = .absent("인공지능 없음. 호출이 실패했습니다.")
            return
        }
        guard generation == recommendGen else { return }
        aiLink = .connected
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
        var points = nearby.filter { Geo.kilometers(latitude, longitude, $0.latitude, $0.longitude) <= radiusKm }
        for mine in myPoints where !points.contains(where: { $0.id == mine.id }) {
            guard Geo.kilometers(latitude, longitude, mine.latitude, mine.longitude) <= radiusKm else { continue }
            points.append(mine)
        }
        if let tapped, !points.contains(where: { $0.id == tapped.id }),
           Geo.kilometers(latitude, longitude, tapped.latitude, tapped.longitude) <= radiusKm {
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
        var merged = next
        for (id, existing) in briefings where merged[id] == nil {
            let kept = myPoints.contains(where: { $0.id == id }) || id == selectedPointId
            if kept { merged[id] = existing }
        }
        briefings = merged
        if geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            aiLink = .absent("인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
        }
        if let selectedPointId, next[selectedPointId] != nil {
            await polish(id: selectedPointId, generation: generation)
        } else if geminiKey.isEmpty == false, let top = next.values.max(by: { $0.score < $1.score }) {
            await polish(id: top.point.id, generation: generation)
        }
    }

    private func polish(id: String, generation: Int) async {
        guard generation == refreshGen, var briefing = briefings[id], briefing.aiScript == nil else { return }
        guard let text = await rewriteBrief(briefing.script) else { return }
        guard generation == refreshGen, briefings[id] != nil else { return }
        briefing.aiScript = text
        briefings[id] = briefing
    }

    private func rewriteBrief(_ script: String) async -> String? {
        let key = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            aiLink = .absent("인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
            return nil
        }
        guard let text = try? await BriefingClient.rewrite(script: script, apiKey: key) else {
            aiLink = .absent("인공지능 없음. 호출이 실패했습니다.")
            return nil
        }
        aiLink = .connected
        return text
    }

    private func snapRoad() {
        roadGen += 1
        let generation = roadGen
        let points = rawTrack
        guard let fallback = points.last else { return }
        Task {
            let snapped = await MapboxGuide.matchRoad(points: points, token: mapboxToken)
            guard generation == self.roadGen else { return }
            if snapped.matched {
                userLat = snapped.latitude
                userLon = snapped.longitude
            } else {
                userLat = fallback.latitude
                userLon = fallback.longitude
            }
            roadNote = snapped.note
        }
    }

    private func chosenPoint() -> FishingPoint? {
        if let id = selectedPointId {
            if let briefing = briefings[id] { return briefing.point }
            if let mine = myPoints.first(where: { $0.id == id }) { return mine }
            if tapped?.id == id { return tapped }
        }
        return tapped
    }

    func noteMap(ok: Bool) {
        let key = mapboxToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            mapLink = .absent("지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
            return
        }
        mapLink = ok ? .connected : .absent("지도 없음. 호출이 실패했습니다.")
    }

    private func noteMapbox(_ reach: GeocodeReach) {
        switch reach {
        case .noKey:
            mapLink = .absent("지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
        case .failed:
            mapLink = .absent("지도 없음. 호출이 실패했습니다.")
        case .ok:
            mapLink = .connected
        }
    }

    private func noteTide(latitude: Double, longitude: Double, generation: Int) async {
        let from = Date()
        let to = from.addingTimeInterval(6 * 3600)
        let report = await PublicTideClient.forecast(
            latitude: latitude,
            longitude: longitude,
            from: from,
            to: to,
            apiKey: dataGoKrKey
        )
        guard generation == refreshGen else { return }
        noteTideReport(report)
    }

    private func noteTideReport(_ report: TideReport) {
        let key = dataGoKrKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            tideLink = .absent("조석 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.")
            return
        }
        if report.samples.isEmpty {
            let reason = report.note.contains("인증키가 이 자료를 거절")
                ? "조석 없음. 인증키가 이 자료를 거절했습니다."
                : (report.note.isEmpty ? "조석 없음. 국립해양조사원 호출이 실패했습니다." : report.note)
            tideLink = .absent(reason)
        } else {
            tideLink = .connected
        }
    }

    private func resetLinksForKeys() {
        mapLink = linkForKey(mapboxToken, emptyReason: "지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.", waiting: "지도 없음. 암호는 있으나 아직 호출하지 않았습니다.", current: mapLink)
        aiLink = linkForKey(geminiKey, emptyReason: "인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.", waiting: "인공지능 없음. 암호는 있으나 아직 호출하지 않았습니다.", current: aiLink)
        tideLink = linkForKey(dataGoKrKey, emptyReason: "조석 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.", waiting: "조석 없음. 인증키는 있으나 아직 호출하지 않았습니다.", current: tideLink)
        youtubeLink = linkForKey(youtubeKey, emptyReason: "유튜브 없음. 비밀 파일에 YOUTUBE_API_KEY 가 없습니다.", waiting: "유튜브 없음. 키는 있으나 아직 호출하지 않았습니다.", current: youtubeLink)
        fishingIndexLink = linkForKey(fishingIndexKey, emptyReason: "바다낚시지수 없음. 비밀 파일에 DATA_GO_KR_FISHING_INDEX_KEY 가 없습니다.", waiting: "바다낚시지수 없음. 키는 있으나 아직 호출하지 않았습니다.", current: fishingIndexLink)
        scubaLink = linkForKey(dataGoKrKey, emptyReason: "스킨스쿠버지수 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.", waiting: "스킨스쿠버지수 없음. 키는 있으나 아직 호출하지 않았습니다.", current: scubaLink)
        if naverClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || naverClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            naverLink = .absent("네이버 검색 없음. 비밀 파일에 NAVER_CLIENT_ID, NAVER_CLIENT_SECRET 이 필요합니다.")
        }
        if geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            googleLink = .absent("구글 검색 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.")
        }
    }

    private func noteWeb(_ load: PlaceWebSearch.Load) {
        naverLink = load.naverConnected ? .connected : .absent(load.naverReason)
        googleLink = load.googleConnected ? .connected : .absent(load.googleReason)
        googleSuggestHtml = load.suggestHtml
    }

    private func noteFishingIndex(_ load: SeaFishingIndexClient.Load) {
        fishingIndexLink = load.connected ? .connected : .absent(load.note)
    }

    private func noteFishingSpots(_ load: FishingSpotStandardClient.Load) {
        fishingSpotLink = load.connected ? .connected : .absent(load.note)
    }

    private func noteScuba(_ load: SkinScubaClient.Load) {
        scubaLink = load.connected ? .connected : .absent(load.note)
    }

    private func noteYouTube(fetched: Bool) {
        let key = youtubeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            youtubeLink = .absent("유튜브 없음. 비밀 파일에 YOUTUBE_API_KEY 가 없습니다.")
            return
        }
        youtubeLink = fetched
            ? .connected
            : .absent("유튜브 없음. 이 지역 공개 영상을 가져오지 못했습니다.")
    }

    private func linkForKey(_ raw: String, emptyReason: String, waiting: String, current: LinkLine) -> LinkLine {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .absent(emptyReason) }
        if current.connected { return current }
        if current.reason == emptyReason || current.reason.isEmpty { return .absent(waiting) }
        return current
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
