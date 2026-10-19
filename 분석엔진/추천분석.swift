import Foundation

// 낚시 계획, 바로가자, 해루질의 순위와 숫자입니다.
// 성공률, 거리, 예상 이동비는 여기서만 계산합니다. 인공지능은 문장만 다듬습니다.

enum TravelEstimate {
    /// 리터당 유류비 기본값입니다. 시세가 아니라 대략 계산용입니다.
    static let wonPerLiter = 1700.0
    /// 일반 승용차 연비 기본값입니다. 킬로미터/리터.
    static let kmPerLiter = 12.0

    static func won(distanceKm: Double) -> Int {
        let raw = (distanceKm * 2 / kmPerLiter) * wonPerLiter
        return Int((raw / 1000.0).rounded()) * 1000
    }
}

enum RecommendEngine {
    static let nowSpan: TimeInterval = 6 * 3600
    /// 분석엔진 조건표에 이미 있는 생물만 해루질에 씁니다. 표에 없는 적기는 만들지 않습니다.
    static let shoreSpecies = ["주꾸미", "갑오징어"]
    static let skinSpecies = ["우럭", "광어", "볼락", "감성돔", "벵에돔"]
    private static let fitFloor = 48

    struct PreparedPoint {
        var point: FishingPoint
        var pack: ConditionPack
        var distanceKm: Double
        var distanceFromUser: Bool
    }

    struct Window {
        var start: Date
        var end: Date
    }

    struct FishingOutcome {
        var picks: [SpotPick]
        var message: String
    }

    struct GleanOutcome {
        var shore: [SpotPick]
        var skin: [SpotPick]
        var message: String
    }

    static func window(on day: Date, startHour: Int, endHour: Int) -> Window {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: startHour, to: startDay) ?? startDay
        var end = calendar.date(byAdding: .hour, value: endHour, to: startDay) ?? start.addingTimeInterval(3600)
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
        }
        return Window(start: start, end: end)
    }

    static func fishing(
        points: [PreparedPoint],
        from: Date,
        to: Date,
        limit: Int,
        preferred: [String],
        tide: TideReport,
        areaTitle: String,
        kind: RecommendKind
    ) -> FishingOutcome {
        let scopeNote = scopeSentence(areaTitle: areaTitle, count: points.count, fewerThan: limit)
        guard !points.isEmpty else {
            if kind == .now {
                return FishingOutcome(picks: [], message: "\(areaTitle) 안에서 공개 자리, 저장 포인트, 찍은 자리가 없습니다.")
            }
            return FishingOutcome(picks: [], message: scopeNote + " 이 반경에서 모은 자리가 없습니다.")
        }
        guard overlaps(points, from: from, to: to) else {
            return FishingOutcome(picks: [], message: scopeNote + " 고른 시간에 해당하는 예보가 없습니다. 예보는 오늘과 내일만 가져옵니다.")
        }
        var ranked: [SpotPick] = []
        var dangerSkipped = 0
        for item in points {
            let moon = MoonClock.info(on: from, longitude: item.point.longitude)
            let hours = FishingAnalyst.hourJudgements(
                point: item.point,
                conditions: item.pack,
                moon: moon,
                preferred: preferred,
                speciesAllow: nil,
                from: from,
                to: to
            )
            let safe = hours.filter { !$0.dangerous }
            guard let best = safe.max(by: { $0.score < $1.score }) else {
                if !hours.isEmpty { dangerSkipped += 1 }
                continue
            }
            let atTime = MoonClock.info(on: best.time, longitude: item.point.longitude)
            ranked.append(makePick(
                item: item,
                best: best,
                moon: atTime,
                tide: tide,
                kind: kind,
                night: nil,
                lowNote: nil
            ))
        }
        ranked.sort(by: better)
        let shown = Array(ranked.prefix(limit))
        return FishingOutcome(
            picks: shown,
            message: fishingMessage(scopeNote: scopeNote, shown: shown.count, limit: limit, candidates: points.count, dangerSkipped: dangerSkipped, tide: tide)
        )
    }

    static func gleaning(
        points: [PreparedPoint],
        from: Date,
        to: Date,
        night: Bool,
        tide: TideReport,
        areaTitle: String
    ) -> GleanOutcome {
        let coastal = points.filter { coastalPlace($0) }
        let scopeNote = scopeSentence(areaTitle: areaTitle, count: points.count, fewerThan: nil)
        guard !points.isEmpty else {
            return GleanOutcome(shore: [], skin: [], message: scopeNote + " 이 반경에서 모은 자리가 없습니다.")
        }
        guard overlaps(points, from: from, to: to) else {
            return GleanOutcome(shore: [], skin: [], message: scopeNote + " 고른 날짜의 예보가 없습니다. 예보는 오늘과 내일만 가져옵니다.")
        }
        let shorePlaces = coastal.filter { shorePlace($0.point.place) }
        let skinPlaces = coastal.filter { skinPlace($0.point.place) }
        let shore = speciesPicks(items: shorePlaces, species: shoreSpecies, from: from, to: to, night: night, tide: tide, kind: .shore)
        let skin = speciesPicks(items: skinPlaces, species: skinSpecies, from: from, to: to, night: night, tide: tide, kind: .skin)
        var lines = [scopeNote]
        let when = night ? "야간 해루질" : "주간 해루질"
        lines.append("\(when)입니다. 갯가와 수중 스킨을 따로 줄 세웠습니다.")
        lines.append("대상 생물은 앱 조건표에 있는 이름만 씁니다. 표에 없는 바지락·낙지·해삼의 적기는 만들지 않습니다.")
        if shorePlaces.isEmpty {
            lines.append("이 반경에는 갯가(백사장·포구·방파제·찍은 자리)로 볼 자리가 없습니다.")
        } else if !shore.misses.isEmpty {
            lines.append("갯가에서 맞는 시간이 없는 생물: \(shore.misses).")
        }
        if skinPlaces.isEmpty {
            lines.append("이 반경에는 수중(갯바위·백사장·방파제·찍은 자리)으로 볼 자리가 없습니다.")
        } else if !skin.misses.isEmpty {
            lines.append("수중에서 맞는 시간이 없는 생물: \(skin.misses).")
        }
        if shore.sawDanger || skin.sawDanger {
            lines.append("바람·파도·천둥이 큰 시간은 추천에서 뺐습니다.")
        }
        lines.append(tide.note)
        return GleanOutcome(shore: shore.picks, skin: skin.picks, message: lines.joined(separator: " "))
    }

    private struct SpeciesBundle {
        var picks: [SpotPick]
        var misses: String
        var sawDanger: Bool
    }

    private static func speciesPicks(
        items: [PreparedPoint],
        species: [String],
        from: Date,
        to: Date,
        night: Bool,
        tide: TideReport,
        kind: RecommendKind
    ) -> SpeciesBundle {
        var picks: [SpotPick] = []
        var misses: [String] = []
        var sawDanger = false
        for name in species {
            var found: [SpotPick] = []
            for item in items {
                let moon = MoonClock.info(on: from, longitude: item.point.longitude)
                let hours = FishingAnalyst.hourJudgements(
                    point: item.point,
                    conditions: item.pack,
                    moon: moon,
                    preferred: [],
                    speciesAllow: [name],
                    from: from,
                    to: to
                )
                let timed = hours.filter { FishingAnalyst.isNightHour($0.time, pack: item.pack) == night }
                let safe = timed.filter { !$0.dangerous }
                if safe.isEmpty, !timed.isEmpty { sawDanger = true }
                let lows = lowMoments(pack: item.pack, tide: tide, from: from, to: to, night: night)
                var chosen: HourJudgement? = nil
                var lowNote: String? = nil
                if kind == .shore {
                    let near = safe.compactMap { hour -> (HourJudgement, Int)? in
                        guard let minutes = minutesFromLow(hour.time, lows: lows.times) else { return nil }
                        return (hour, minutes)
                    }
                    guard let best = near.max(by: { $0.0.score < $1.0.score }), best.0.score >= fitFloor else { continue }
                    chosen = best.0
                    lowNote = "간조 시각과 \(best.1)분 차이입니다. 간조 기준은 \(lows.source)입니다."
                } else {
                    guard let best = safe.max(by: { $0.score < $1.score }), best.score >= fitFloor else { continue }
                    guard let hour = nearestHour(best.time, in: item.pack) else { continue }
                    if (hour.waveM ?? 0) >= 1.2 || (hour.windMs ?? 0) >= 10 { continue }
                    chosen = best
                    lowNote = nil
                }
                guard let chosenHour = chosen else { continue }
                let atTime = MoonClock.info(on: chosenHour.time, longitude: item.point.longitude)
                found.append(makePick(
                    item: item,
                    best: chosenHour,
                    moon: atTime,
                    tide: tide,
                    kind: kind,
                    night: night,
                    lowNote: lowNote
                ))
            }
            found.sort(by: better)
            if found.isEmpty {
                misses.append(name)
            } else {
                picks.append(contentsOf: found.prefix(3))
            }
        }
        return SpeciesBundle(picks: picks, misses: misses.joined(separator: ", "), sawDanger: sawDanger)
    }

    private static func makePick(
        item: PreparedPoint,
        best: HourJudgement,
        moon: MoonInfo,
        tide: TideReport,
        kind: RecommendKind,
        night: Bool?,
        lowNote: String?
    ) -> SpotPick {
        let hour = nearestHour(best.time, in: item.pack)
        let publicNote = PublicGroundNote.make(latitude: item.point.latitude, longitude: item.point.longitude)
        let facts = spotFacts(point: item.point, hour: hour, moon: moon, fromUser: item.distanceFromUser)
        var why = measurementLines(hour: hour, moon: moon)
        why.append(contentsOf: best.reasons.map { "조건표: \($0)" })
        if let lowNote { why.append(lowNote) }
        if let official = officialTideLine(at: best.time, tide: tide) { why.append(official) }
        why.append(tide.note)
        var risks = conditionRisks(hour: hour, usedSea: item.pack.usedSea)
        if kind == .shore || kind == .skin {
            risks.append(contentsOf: gleanRisks(night: night == true, skin: kind == .skin))
        }
        let reasonCore = best.reasons.prefix(2).joined(separator: ", ")
        let reason = reasonCore.isEmpty ? "이 시각의 물때, 바람, 수온을 보고 골랐습니다." : reasonCore
        let cost = TravelEstimate.won(distanceKm: item.distanceKm)
        let pickId = "\(kind.rawValue)|\(item.point.id)|\(best.species)|\(Int(best.time.timeIntervalSince1970))"
        let script = factScript(
            point: item.point,
            when: best.time,
            rate: best.score,
            distanceKm: item.distanceKm,
            cost: cost,
            species: best.species,
            reason: reason,
            why: why,
            facts: facts,
            risks: risks,
            publicSummary: publicNote.summary,
            publicWarnings: publicNote.warnings
        )
        return SpotPick(
            id: pickId,
            kind: kind,
            point: item.point,
            when: best.time,
            successRate: min(100, max(0, best.score)),
            distanceKm: item.distanceKm,
            costWon: cost,
            species: best.species,
            reason: reason,
            whyLines: why,
            facts: facts,
            risks: risks,
            publicSummary: publicNote.summary,
            publicWarnings: publicNote.warnings,
            factScript: script,
            aiReason: nil
        )
    }

    private static func better(_ left: SpotPick, _ right: SpotPick) -> Bool {
        if left.successRate != right.successRate { return left.successRate > right.successRate }
        return (left.distanceKm ?? 999) < (right.distanceKm ?? 999)
    }

    private static func overlaps(_ points: [PreparedPoint], from: Date, to: Date) -> Bool {
        points.contains { item in
            item.pack.hours.contains { $0.time >= from && $0.time < to }
        }
    }

    private static func coastalPlace(_ item: PreparedPoint) -> Bool {
        if item.point.water == .fresh || item.point.place == .freshwater || item.point.place == .boat { return false }
        return item.pack.usedSea
    }

    private static func shorePlace(_ place: PlaceKind) -> Bool {
        place == .beach || place == .harbor || place == .pier || place == .custom
    }

    private static func skinPlace(_ place: PlaceKind) -> Bool {
        place == .rock || place == .beach || place == .pier || place == .custom
    }

    private static func lowMoments(
        pack: ConditionPack,
        tide: TideReport,
        from: Date,
        to: Date,
        night: Bool
    ) -> (times: [Date], source: String) {
        if tide.usable {
            let lows = TideReading.lowTimes(tide.samples).filter { date in
                date >= from.addingTimeInterval(-90 * 60) && date < to.addingTimeInterval(90 * 60)
                    && FishingAnalyst.isNightHour(date, pack: pack) == night
            }
            if !lows.isEmpty {
                return (lows, "국립해양조사원 \(tide.stationName)")
            }
        }
        let model = pack.hours.filter {
            $0.time >= from && $0.time < to && $0.tide == .low && FishingAnalyst.isNightHour($0.time, pack: pack) == night
        }.map(\.time)
        return (model, "바다 예보 모델")
    }

    private static func minutesFromLow(_ date: Date, lows: [Date]) -> Int? {
        guard let nearest = lows.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) else { return nil }
        let minutes = abs(nearest.timeIntervalSince(date)) / 60
        guard minutes <= 90 else { return nil }
        return Int(minutes.rounded())
    }

    private static func nearestHour(_ date: Date, in pack: ConditionPack) -> HourCondition? {
        pack.hours.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    private static func officialTideLine(at date: Date, tide: TideReport) -> String? {
        guard !tide.samples.isEmpty,
              let sample = tide.samples.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }),
              abs(sample.time.timeIntervalSince(date)) <= 45 * 60 else { return nil }
        return "국립해양조사원 \(tide.stationName) 조위 약 \(Int(sample.heightCm.rounded()))cm, 시각 \(FieldFormat.clock(sample.time))."
    }

    private static func spotFacts(point: FishingPoint, hour: HourCondition?, moon: MoonInfo, fromUser: Bool) -> SpotFacts {
        let waterLabel = hour?.seaC == nil ? "기온 \(FieldFormat.temp(hour?.airC))" : "수온 \(FieldFormat.temp(hour?.seaC))"
        var place = "\(point.place.title), \(point.water.title)."
        if point.isMine {
            place += " 내가 저장한 자리."
        } else if point.source == "찍은자리" {
            place += " 지도에서 찍은 자리."
        } else {
            place += " 공개 지도에서 찾은 자리."
        }
        if !point.bottom.isEmpty { place += " 바닥 메모: \(point.bottom)." }
        if !point.targetMemo.isEmpty { place += " 노리는 고기 메모: \(point.targetMemo)." }
        if !point.memo.isEmpty { place += " 메모: \(point.memo)." }
        place += fromUser ? " 거리는 현재 위치 기준." : " 거리는 고른 지역 중심 기준."
        return SpotFacts(
            weather: FieldFormat.sky(hour?.weatherCode),
            wind: "\(FieldFormat.wind(hour?.windMs)) \(FieldFormat.direction(hour?.windDeg))",
            pressure: hour?.pressureHpa.map { String(format: "%.0f hPa", $0) } ?? "모름",
            rain: hour?.rainMm.map { String(format: "%.1fmm", $0) } ?? "모름",
            water: waterLabel,
            wave: FieldFormat.meters(hour?.waveM),
            seaLevel: hour?.seaLevelM.map { String(format: "%.2fm", $0) } ?? "모름",
            tide: hour?.tide.title ?? "모름",
            moon: "\(moon.name) · \(moon.tideName)",
            place: place
        )
    }

    private static func measurementLines(hour: HourCondition?, moon: MoonInfo) -> [String] {
        guard let hour else { return ["이 시각의 예보 칸을 찾지 못했습니다."] }
        var lines = [
            "날씨 \(FieldFormat.sky(hour.weatherCode))",
            "바람 \(FieldFormat.wind(hour.windMs)) \(FieldFormat.direction(hour.windDeg))",
            "기압 \(hour.pressureHpa.map { String(format: "%.0f hPa", $0) } ?? "모름")",
            "강수 \(hour.rainMm.map { String(format: "%.1fmm", $0) } ?? "모름")",
        ]
        if let sea = hour.seaC {
            lines.append(String(format: "수온 %.0f도", sea))
        } else if let air = hour.airC {
            lines.append(String(format: "바다 수온이 없어 기온 %.0f도로 봤습니다", air))
        }
        lines.append("파도 \(FieldFormat.meters(hour.waveM))")
        lines.append("해수면 \(hour.seaLevelM.map { String(format: "%.2fm", $0) } ?? "모름")")
        lines.append("물때 \(hour.tide.title)")
        lines.append("달 \(moon.name), \(moon.tideName)")
        return lines
    }

    private static func conditionRisks(hour: HourCondition?, usedSea: Bool) -> [String] {
        var lines: [String] = []
        if let hour {
            if (hour.windMs ?? 0) >= 8 {
                lines.append("바람이 \(FieldFormat.wind(hour.windMs))입니다. 발밑과 파도를 먼저 보세요.")
            }
            if usedSea, (hour.waveM ?? 0) >= 1.2 {
                lines.append("파고가 \(FieldFormat.meters(hour.waveM))입니다. 월파가 있으면 들어가지 마세요.")
            }
            if (hour.weatherCode ?? 0) >= 95 {
                lines.append("천둥 예보가 있습니다. 낚싯대는 피뢰침이 됩니다.")
            }
        }
        if usedSea {
            lines.append("들물·날물 높이는 바다 예보 모델일 수 있습니다. 서해는 실제 조차가 더 클 수 있습니다.")
        } else {
            lines.append("이 자리는 바다 칸과 멀어 물때 대신 기온과 시간을 봤습니다.")
        }
        return lines
    }

    private static func gleanRisks(night: Bool, skin: Bool) -> [String] {
        var lines = ["마을어장, 금어기, 포획금지는 경고로만 보여 줍니다. 제한을 피해서 들어가는 방법은 적지 않습니다."]
        if skin {
            lines.append("수중은 맨몸 잠수(스킨)입니다. 얕은 물에서도 기절할 수 있으니 혼자 들어가지 마세요.")
            lines.append("조류가 세거나 파도가 높으면 들어가지 마세요.")
            if night { lines.append("밤 수중은 시야가 거의 없습니다.") }
        } else {
            lines.append("갯벌과 얕은 물은 들물이 시작하면 발이 빠지거나 육지와 끊길 수 있습니다. 물이 차오르기 전에 나오세요.")
            if night { lines.append("밤에는 물길과 웅덩이가 잘 보이지 않습니다.") }
        }
        return lines
    }

    private static func scopeSentence(areaTitle: String, count: Int, fewerThan: Int?) -> String {
        var text = "\(areaTitle)만 봤습니다. 후보는 주변 공개 자리, 저장 포인트, 지도에서 찍은 자리입니다. 전국은 찾지 않았습니다. 모은 후보는 \(count)곳입니다."
        if let limit = fewerThan, count < limit {
            text += " \(limit)곳보다 적어서 있는 만큼만 보여 줍니다."
        }
        return text
    }

    private static func fishingMessage(
        scopeNote: String,
        shown: Int,
        limit: Int,
        candidates: Int,
        dangerSkipped: Int,
        tide: TideReport
    ) -> String {
        var lines = [scopeNote]
        if shown == 0 {
            lines.append("조건이 되는 자리가 없습니다.")
        } else if shown < limit, candidates >= limit {
            lines.append("조건이 되는 자리는 \(shown)곳입니다.")
        }
        if dangerSkipped > 0 {
            lines.append("바람·파도·천둥 때문에 \(dangerSkipped)곳은 추천에서 뺐습니다.")
        }
        if shown > 0 {
            lines.append("순위는 그 시간의 조건 적합도가 높은 순이고, 같으면 가까운 순입니다.")
        }
        lines.append(tide.note)
        return lines.joined(separator: " ")
    }

    private static func factScript(
        point: FishingPoint,
        when: Date,
        rate: Int,
        distanceKm: Double,
        cost: Int,
        species: String,
        reason: String,
        why: [String],
        facts: SpotFacts,
        risks: [String],
        publicSummary: String,
        publicWarnings: [String]
    ) -> String {
        [
            "자리: \(point.name)",
            "시각: \(FieldFormat.dayClock(when))",
            "성공률: \(rate). 조건 적합도이며 조과 보장이 아님",
            "거리: \(FieldFormat.distance(distanceKm))",
            "예상 이동비: \(FieldFormat.money(cost)). 왕복 유류비 대략값. 통행료와 선비 아님",
            "대상: \(species)",
            "이유: \(reason)",
            "사실: \(why.joined(separator: " / "))",
            "지역: \(facts.place)",
            "주의: \(risks.joined(separator: " / "))",
            "공공자료: \(publicSummary). \(publicWarnings.joined(separator: " / "))",
        ].joined(separator: "\n")
    }
}
