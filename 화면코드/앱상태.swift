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
    /// 바다해도만 씁니다. 조석예보 키와 섞지 않습니다.
    @Published var haereumKey = ""
    /// 유튜브 공개 영상 검색만 씁니다. 로그인이나 비공개 영상은 보지 않습니다.
    @Published var youtubeKey = ""
    /// 바다낚시지수 조회만 씁니다. 조석예보 키와 다릅니다.
    @Published var fishingIndexKey = ""
    @Published var planPicks: [SpotPick] = []
    @Published var nowPicks: [SpotPick] = []
    @Published var shorePicks: [SpotPick] = []
    @Published var skinPicks: [SpotPick] = []
    @Published var planMessage = "기준점 일대의 공개 글, 유튜브, 바다낚시지수, 전국낚시터를 읽어 최대 10곳을 줄 세웁니다."
    @Published var nowMessage = "현재 위치 일대의 공개 글, 유튜브, 바다낚시지수, 전국낚시터를 읽어 최대 3곳을 줄 세웁니다."
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
    @Published var savedTimes: [String: SavedSpotTimes] = [:]
    @Published var savedTimesNote = "저장한 자리의 낚시 시간과 해루질 시간을 받은 예보로 계산합니다."

    private let locator = LocationFixer()
    private var cache: [String: ConditionPack] = [:]
    private var refreshGen = 0
    private var recommendGen = 0
    private var savedPlanGen = 0
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
        mapboxToken = secrets.mapbox
        geminiKey = secrets.gemini
        dataGoKrKey = secrets.dataGoKr
        haereumKey = secrets.haereum
        youtubeKey = secrets.youtube
        fishingIndexKey = secrets.fishingIndex
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
            locationText = userLat == nil ? "현재 위치를 가져오는 중" : "현재 위치를 사용 중"
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
        statusText = "자리를 찍었습니다. 분석을 누르면 이 자리를 계산합니다."
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
        Task {
            let found = await PlaceNameClient.forward(
                query: trimmed,
                latitude: centerLat,
                longitude: centerLon,
                token: mapboxToken
            )
            noteMapbox(found.reach)
            searchHits = found.hits
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
        if tapped?.id == id, tapped?.source == "찍은자리", briefings[id] == nil {
            return
        }
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
            if let text = await rewriteBrief(briefing.script) {
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
        refreshSavedPlans()
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
            if let text = await rewriteBrief(briefing.script) {
                briefing.aiScript = text
            }
            briefings[point.id] = briefing
        }
        refreshSavedPlans()
    }

    func deleteMine(_ point: FishingPoint) {
        myPoints.removeAll { $0.id == point.id }
        briefings.removeValue(forKey: point.id)
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
                guard let pack = try? await self.cachedConditions(latitude: point.latitude, longitude: point.longitude) else {
                    next[point.id] = SavedSpotTimes(
                        pointId: point.id,
                        fishingLines: ["날씨와 바다 정보를 가져오지 못했습니다. 시간을 만들지 않았습니다."],
                        dayLines: ["날씨와 바다 정보를 가져오지 못했습니다."],
                        nightLines: ["날씨와 바다 정보를 가져오지 못했습니다."]
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
                        "\(FieldFormat.dayClock($0.when)) · \($0.species). 받은 물때·날씨로 고른 시간입니다. 알림은 보내지 않습니다."
                    }
                let dayPicks = [visit.dayShore, visit.daySkin].compactMap { $0 }
                let nightPicks = [visit.nightShore, visit.nightSkin].compactMap { $0 }
                let dayLines = dayPicks.isEmpty
                    ? ["받은 예보 안에서 주간 해루질에 맞는 시간이 없습니다."]
                    : dayPicks.map { self.gleanLine($0) }
                let nightLines = nightPicks.isEmpty
                    ? ["받은 예보 안에서 야간 해루질에 맞는 시간이 없습니다."]
                    : nightPicks.map { self.gleanLine($0) }
                next[point.id] = SavedSpotTimes(
                    pointId: point.id,
                    fishingLines: fishingLines,
                    dayLines: dayLines,
                    nightLines: nightLines
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
        return "\(FieldFormat.dayClock(pick.when)) · \(place) · \(pick.species). 받은 물때·날씨로 고른 시간입니다."
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
            ? "공개 글, 유튜브, 바다낚시지수, 전국낚시터를 읽는 중"
            : "주변 자리, 스킨스쿠버지수, 물때, 수온을 계산하는 중"
        writeRecommendMessage(waiting, slot: slot)
        Task {
            let loaded = mentions
                ? await self.loadMentionedContext(scope: scope, requireUser: requireUser, from: from, to: to)
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
        scope: RecommendScope,
        requireUser: Bool,
        from: Date,
        to: Date
    ) async -> Result<RecommendContext, RecommendMessageError> {
        guard let center = recommendCenter(scope: scope, requireUser: requireUser) else {
            if requireUser || scope == .here {
                return .failure(RecommendMessageError(message: "현재 위치가 없습니다. 위치 권한을 허용해 주세요."))
            }
            return .failure(RecommendMessageError(message: "저장된 지역이 없습니다. 지도에서 지역을 맞춘 뒤 이 지역 저장을 누르세요."))
        }
        let signature = String(format: "%.3f,%.3f,%.0f", center.lat, center.lon, center.radius)
        let remembered = mentionMemory
        let located: [FishingPoint]
        let intro: String
        let title: String
        if let remembered, remembered.signature == signature, Date().timeIntervalSince(remembered.at) < 600, !remembered.points.isEmpty {
            located = remembered.points
            intro = remembered.intro
            title = remembered.title
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
            noteFishingIndex(index)
            noteFishingSpots(spots)
            if !index.connected {
                OfficialNotes.blocked = index.note
            }
            var merged = outcome.points + index.points + spots.points
            var kept: [FishingPoint] = []
            for point in merged {
                if kept.contains(where: { Geo.kilometers($0.latitude, $0.longitude, point.latitude, point.longitude) < 0.4 && $0.name == point.name }) {
                    continue
                }
                kept.append(point)
            }
            SeaFishingIndexClient.attach(to: kept, anchors: index.points)
            guard !kept.isEmpty else {
                var reason = [outcome.failure, index.note, spots.note].compactMap { $0 }.filter { !$0.isEmpty }
                if reason.isEmpty { reason = ["추천할 자리를 정하지 못했습니다. 없는 자리는 만들지 않았습니다."] }
                return .failure(RecommendMessageError(message: reason.joined(separator: " ")))
            }
            located = kept
            var lines = [outcome.points.isEmpty ? (outcome.failure ?? "") : outcome.intro, index.note, spots.note]
            intro = lines.filter { !$0.isEmpty }.joined(separator: " ")
            title = anchorName
            mentionMemory = MentionMemory(signature: signature, at: Date(), points: located, intro: intro, title: title)
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
        tideLink = report.samples.isEmpty
            ? .absent("조석 없음. 국립해양조사원 호출이 실패했습니다.")
            : .connected
    }

    private func resetLinksForKeys() {
        mapLink = linkForKey(mapboxToken, emptyReason: "지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.", waiting: "지도 없음. 암호는 있으나 아직 호출하지 않았습니다.", current: mapLink)
        aiLink = linkForKey(geminiKey, emptyReason: "인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다.", waiting: "인공지능 없음. 암호는 있으나 아직 호출하지 않았습니다.", current: aiLink)
        tideLink = linkForKey(dataGoKrKey, emptyReason: "조석 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.", waiting: "조석 없음. 인증키는 있으나 아직 호출하지 않았습니다.", current: tideLink)
        youtubeLink = linkForKey(youtubeKey, emptyReason: "유튜브 없음. 비밀 파일에 YOUTUBE_API_KEY 가 없습니다.", waiting: "유튜브 없음. 키는 있으나 아직 호출하지 않았습니다.", current: youtubeLink)
        fishingIndexLink = linkForKey(fishingIndexKey, emptyReason: "바다낚시지수 없음. 비밀 파일에 DATA_GO_KR_FISHING_INDEX_KEY 가 없습니다.", waiting: "바다낚시지수 없음. 키는 있으나 아직 호출하지 않았습니다.", current: fishingIndexLink)
        scubaLink = linkForKey(dataGoKrKey, emptyReason: "스킨스쿠버지수 없음. 비밀 파일에 DATA_GO_KR_SERVICE_KEY 가 없습니다.", waiting: "스킨스쿠버지수 없음. 키는 있으나 아직 호출하지 않았습니다.", current: scubaLink)
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
