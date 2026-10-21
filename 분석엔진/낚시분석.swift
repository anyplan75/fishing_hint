import Foundation

// 한 시간마다 수온, 물때, 바람, 파도, 비, 기압, 달을 점수로 바꿉니다.
// 가장 높은 고기와 시간대를 고른 뒤, 그 조건에 맞는 채비를 붙입니다.
// 위험하면 점수가 높아도 나가지 말라고 바꿉니다.

struct HourJudgement {
    var time: Date
    var score: Int
    var species: String
    var reasons: [String]
    var dangerous: Bool
}

private struct SpeciesRule {
    var name: String
    var water: WaterKind
    var places: Set<PlaceKind>
    var months: Set<Int>
    var tempMin: Double
    var tempMax: Double
    var bestMin: Double
    var bestMax: Double
    var flood: Bool
    var ebb: Bool
    var slack: Bool
    var prefersNight: Bool
    var prefersDawn: Bool
    var dayOk: Bool
    var maxWind: Double
    var maxWave: Double
}

enum FishingAnalyst {
    static func brief(
        point: FishingPoint,
        conditions: ConditionPack,
        moon: MoonInfo,
        preferred: [String],
        distanceKm: Double?,
        now: Date = Date()
    ) -> PointBriefing {
        let recorded = TackleBook.recordedNames(point: point)
        var rules = filteredRules(point: point, conditions: conditions, preferred: preferred)
        let matched = rules.filter { recorded.contains($0.name) }
        if !matched.isEmpty { rules = matched }
        let stained = recentRain(conditions, now: now) >= 4
        let indexes = Array(conditions.hours.indices)
        var table: [[Int]] = []
        var reasonTable: [[[String]]] = []

        for rule in rules {
            var scores: [Int] = []
            var reasons: [[String]] = []
            for hour in conditions.hours {
                let result = scoreHour(rule: rule, hour: hour, pack: conditions, moon: moon, point: point, stained: stained)
                scores.append(result.0)
                reasons.append(result.1)
            }
            table.append(scores)
            reasonTable.append(reasons)
        }

        let future = indexes.filter { conditions.hours[$0].time >= now.addingTimeInterval(-30 * 60) }
        let bestIndex = bestRuleIndex(table: table, future: future)
        let scores = table[bestIndex]
        let speciesLabel = recorded.isEmpty ? TackleBook.missingSpecies : recorded.joined(separator: ", ")
        let windows = makeWindows(
            scores: scores,
            reasons: reasonTable[bestIndex],
            hours: conditions.hours,
            species: speciesLabel,
            future: future
        )
        let peak = windows.map(\.score).max() ?? (future.map { scores[$0] }.max() ?? 0)
        let bookNames = recorded.filter { TackleBook.speciesOrder.contains($0) }
        let tackle: TacklePlan
        if let first = bookNames.first {
            var plan = TackleBook.plan(for: first, context: context(from: conditions, now: now, stained: stained, point: point))
            plan.species = speciesLabel
            if bookNames.count > 1 {
                plan.summary = "출처에 적힌 어종은 \(speciesLabel)입니다. 채비는 그 가운데 \(first) 기준입니다. " + plan.summary
            }
            tackle = plan
        } else if recorded.isEmpty {
            tackle = TackleBook.unrecordedPlan()
        } else {
            var plan = TackleBook.unrecordedPlan()
            plan.species = speciesLabel
            plan.summary = "출처에 적힌 어종은 \(speciesLabel)입니다. 이 이름의 채비 규격은 없어 규격을 만들지 않습니다."
            tackle = plan
        }

        var alternate: TacklePlan?
        var alternateNote: String?
        if bookNames.count > 1 {
            let second = bookNames[1]
            alternate = TackleBook.plan(for: second, context: context(from: conditions, now: now, stained: stained, point: point))
            alternateNote = "출처에 같이 적힌 \(second) 채비입니다. 날짜로 다른 어종을 넣지 않습니다."
        }

        let shownWindows = windows.map { window -> AttackWindow in
            var copy = window
            copy.species = speciesLabel
            if recorded.isEmpty {
                copy.reasons = copy.reasons.filter { line in
                    !TackleBook.speciesOrder.contains { line.contains($0) }
                }
                if copy.reasons.isEmpty {
                    copy.reasons = ["기록된 어종이 없어 어종 조건은 붙이지 않았습니다."]
                }
            }
            return copy
        }
        let conditionLines = Self.conditionLines(
            names: recorded,
            hour: hour(near: now, in: conditions),
            sea: conditions.usedSea
        )

        let risks = riskLines(conditions: conditions, now: now, usedSea: conditions.usedSea)
        let dangerousNow = isDanger(hour(near: now, in: conditions), sea: conditions.usedSea)
        let safeWindow = windows.first { $0.score >= 62 && !windowIsDanger($0, conditions: conditions) }
        let call = decide(dangerousNow: dangerousNow, safeWindow: safeWindow, peak: peak, now: now)
        let headline = headlineText(call: call, species: speciesLabel, method: tackle.method, window: shownWindows.first, dangerousNow: dangerousNow)
        let summary = summaryText(point: point, species: speciesLabel, call: call, window: shownWindows.first, peak: peak)
        let nowLine = nowLine(conditions: conditions, moon: moon, now: now)
        var script = scriptText(
            point: point,
            call: call,
            headline: headline,
            nowLine: nowLine,
            windows: shownWindows,
            tackle: tackle,
            alternateNote: alternateNote,
            risks: risks,
            moon: moon
        )
        if !conditionLines.isEmpty {
            script += "\n어종 조건:\n" + conditionLines.joined(separator: "\n")
        }

        return PointBriefing(
            point: point,
            distanceKm: distanceKm,
            call: call,
            score: call == .danger ? min(peak, 40) : peak,
            headline: headline,
            summary: summary,
            nowLine: nowLine,
            windows: shownWindows,
            hourScores: scores,
            tackle: tackle,
            alternate: alternate,
            alternateNote: alternateNote,
            risks: risks,
            script: script,
            aiScript: nil,
            conditions: conditions,
            conditionLines: conditionLines
        )
    }

    private static func filteredRules(point: FishingPoint, conditions: ConditionPack, preferred: [String]) -> [SpeciesRule] {
        var rules = catalog
        let water = resolvedWater(point: point, conditions: conditions)
        rules = rules.filter { $0.water == water || water == .unknown }
        if water == .unknown {
            rules = catalog
        }
        if !preferred.isEmpty {
            let picked = rules.filter { preferred.contains($0.name) }
            if !picked.isEmpty { rules = picked }
        }
        return rules.isEmpty ? catalog : rules
    }

    private static func resolvedWater(point: FishingPoint, conditions: ConditionPack) -> WaterKind {
        if point.water != .unknown { return point.water }
        if point.place == .freshwater { return .fresh }
        if conditions.usedSea { return .sea }
        return .fresh
    }

    private static func bestRuleIndex(table: [[Int]], future: [Int]) -> Int {
        var best = 0
        var bestScore = -1
        for (index, scores) in table.enumerated() {
            let peak = future.map { scores[$0] }.max() ?? 0
            if peak > bestScore {
                bestScore = peak
                best = index
            }
        }
        return best
    }

    private static func alternateIndex(table: [[Int]], best: Int, future: [Int], hours: [HourCondition]) -> Int? {
        guard let bestHour = future.max(by: { table[best][$0] < table[best][$1] }) else { return nil }
        var pick: Int?
        var pickScore = 0
        for (index, scores) in table.enumerated() where index != best {
            guard let hour = future.max(by: { scores[$0] < scores[$1] }) else { continue }
            let score = scores[hour]
            let gap = abs(hours[hour].time.timeIntervalSince(hours[bestHour].time))
            if score > pickScore && gap >= 3 * 3600 {
                pickScore = score
                pick = index
            }
        }
        return pick
    }

    private static func scoreHour(
        rule: SpeciesRule,
        hour: HourCondition,
        pack: ConditionPack,
        moon: MoonInfo,
        point: FishingPoint,
        stained: Bool
    ) -> (Int, [String]) {
        if isDanger(hour, sea: pack.usedSea && rule.water == .sea) {
            return (0, ["이 시간은 바람·파도·천둥 때문에 제외"])
        }

        var reasons: [String] = []
        let water = point.measuredTempC ?? (rule.water == .fresh ? (hour.seaC ?? hour.airC) : (hour.seaC ?? hour.airC))
        let waterName = (point.measuredTempC != nil || hour.seaC != nil) ? "수온" : "기온"
        let tempSpan = String(format: "잘 맞는 범위 %.0f~%.0f도, 가능한 범위 %.0f~%.0f도", rule.bestMin, rule.bestMax, rule.tempMin, rule.tempMax)
        var tempPoints = 8
        if let water {
            if water >= rule.bestMin && water <= rule.bestMax {
                tempPoints = 35
                reasons.append(String(format: "%@ %@: 지금 %.0f도. %@. 지금은 잘 맞는 범위 안", rule.name, waterName, water, tempSpan))
            } else if water >= rule.tempMin && water <= rule.tempMax {
                tempPoints = 22
                reasons.append(String(format: "%@ %@: 지금 %.0f도. %@. 지금은 가능한 범위 안", rule.name, waterName, water, tempSpan))
            } else {
                tempPoints = 4
                reasons.append(String(format: "%@ %@: 지금 %.0f도. %@. 지금은 가능한 범위 밖", rule.name, waterName, water, tempSpan))
            }
            if point.measuredTempC == nil && hour.seaC == nil {
                tempPoints = min(tempPoints, 18)
                reasons.append("\(rule.name) 바다 수온이 없어 기온으로만 가늠")
            }
        } else {
            reasons.append("\(rule.name) 수온: 지금 값 없음. \(tempSpan).")
        }

        let month = Calendar.current.component(.month, from: hour.time)
        let monthPoints = rule.months.contains(month) ? 10 : 2

        var tidePoints = 8
        if pack.usedSea && rule.water == .sea {
            let liked = tidePreference(rule)
            switch hour.tide {
            case .flood where rule.flood:
                tidePoints = 20
                reasons.append("\(rule.name) 물때: 지금 들물. 이 어종은 \(liked). 지금은 맞음")
            case .ebb where rule.ebb:
                tidePoints = 18
                reasons.append("\(rule.name) 물때: 지금 날물. 이 어종은 \(liked). 지금은 맞음")
            case .high where rule.slack, .low where rule.slack:
                tidePoints = 16
                reasons.append("\(rule.name) 물때: 지금 \(hour.tide.title). 이 어종은 \(liked). 지금은 맞음")
            case .unknown:
                tidePoints = 8
                reasons.append("\(rule.name) 물때: 지금 값 없음. 이 어종은 \(liked)")
            default:
                tidePoints = 6
                reasons.append("\(rule.name) 물때: 지금 \(hour.tide.title). 이 어종은 \(liked). 지금은 이 어종의 물때와 다름")
            }
        }

        let timePoints = timeScore(rule: rule, hour: hour, pack: pack, reasons: &reasons)
        var sky = 15
        if let wind = hour.windMs {
            if wind > rule.maxWind { sky -= 12 }
            else if wind >= 8 { sky -= 7 }
            let windJudge = wind > rule.maxWind ? "기준보다 셈" : "기준 안"
            reasons.append(String(format: "%@ 바람: 지금 %.0fm/s. 이 어종 기준은 %.0fm/s 이하. 지금은 %@", rule.name, wind, rule.maxWind, windJudge))
        } else {
            reasons.append(String(format: "%@ 바람: 지금 값 없음. 이 어종 기준은 %.0fm/s 이하", rule.name, rule.maxWind))
        }
        if rule.water == .sea {
            if let wave = hour.waveM {
                if wave > rule.maxWave { sky -= 10 }
                else if wave >= 1.0 { sky -= 4 }
                let waveJudge = wave > rule.maxWave ? "기준보다 큼" : "기준 안"
                reasons.append(String(format: "%@ 파도: 지금 %.1fm. 이 어종 기준은 %.1fm 이하. 지금은 %@", rule.name, wave, rule.maxWave, waveJudge))
            } else if pack.usedSea {
                reasons.append(String(format: "%@ 파도: 지금 값 없음. 이 어종 기준은 %.1fm 이하", rule.name, rule.maxWave))
            }
        }
        if (hour.rainMm ?? 0) >= 2 { sky -= 4; reasons.append("비가 오는 시간") }
        sky = max(0, sky)

        var moonPoints = 0
        if moon.majors.contains(where: { $0.contains(hour.time) }) {
            moonPoints = 8
            reasons.append("달 남중 전후")
        } else if moon.minors.contains(where: { $0.contains(hour.time) }) {
            moonPoints = 4
        }

        var pressurePoints = 0
        if let trend = pressureTrend(at: hour.time, pack: pack) {
            if trend < -1.5 && trend > -8 {
                pressurePoints = 5
                reasons.append("기압이 천천히 내려가는 중")
            } else if trend <= -8 {
                reasons.append("기압이 급하게 내려가 날씨가 바뀔 수 있음")
            }
        }

        var bonus = 0
        if point.bottom.contains("모래"), rule.name == "광어" { bonus += 6; reasons.append("모래 바닥") }
        if point.bottom.contains("암") || point.bottom.contains("여"), ["감성돔", "벵에돔", "우럭"].contains(rule.name) {
            bonus += 6
            reasons.append("암초·여 바닥")
        }
        if point.bottom.contains("수초"), rule.name == "붕어" { bonus += 6 }
        if point.targetMemo.contains(rule.name) { bonus += 8; reasons.append("이 포인트에서 노리던 고기") }
        if stained, ["광어", "농어", "붕어", "배스"].contains(rule.name) {
            bonus += 3
            reasons.append("탁한 물색에 버티는 고기")
        }

        var total = tempPoints + monthPoints + tidePoints + timePoints + sky + moonPoints + pressurePoints + bonus
        total = Int(Double(total) * placeFactor(rule: rule, place: point.place))
        return (min(100, max(0, total)), reasons)
    }

    private static func timeScore(rule: SpeciesRule, hour: HourCondition, pack: ConditionPack, reasons: inout [String]) -> Int {
        let night = isNight(hour.time, pack: pack)
        let dawn = isDawnDusk(hour.time, pack: pack)
        if rule.prefersNight && night {
            reasons.append("밤 시간")
            return 15
        }
        if rule.prefersDawn && dawn {
            reasons.append("해 질녘·해 뜰 무렵")
            return 15
        }
        if night && !rule.prefersNight && !rule.dayOk { return 4 }
        if !night && rule.prefersNight && !rule.dayOk { return 3 }
        if rule.dayOk { return 9 }
        return 6
    }

    private static func placeFactor(rule: SpeciesRule, place: PlaceKind) -> Double {
        if place == .custom || place == .freshwater && rule.water == .fresh { return 1 }
        if rule.places.contains(place) { return 1 }
        if place == .boat { return 0.85 }
        return 0.72
    }

    private static func makeWindows(
        scores: [Int],
        reasons: [[String]],
        hours: [HourCondition],
        species: String,
        future: [Int]
    ) -> [AttackWindow] {
        let futureSet = Set(future)
        var windows: [AttackWindow] = []
        var start: Int?
        var lastGood: Int?
        func close(_ from: Int, _ to: Int) {
            let slice = Array(from...to)
            let peak = slice.max { scores[$0] < scores[$1] } ?? from
            var seen = Set<String>()
            let unique = reasons[peak].filter { seen.insert($0).inserted }
            windows.append(AttackWindow(
                id: "\(hours[from].time.timeIntervalSince1970)",
                start: hours[from].time,
                end: hours[to].time.addingTimeInterval(3600),
                score: scores[peak],
                species: species,
                reasons: Array(unique.prefix(3))
            ))
        }
        for index in hours.indices where futureSet.contains(index) {
            if scores[index] >= 64 {
                if start == nil { start = index }
                lastGood = index
            } else if let from = start, let good = lastGood, scores[index] < 58 {
                close(from, good)
                start = nil
                lastGood = nil
            }
        }
        if let from = start, let good = lastGood { close(from, good) }
        return windows.sorted { $0.score > $1.score }.prefix(3).map { $0 }
    }

    private static func decide(dangerousNow: Bool, safeWindow: AttackWindow?, peak: Int, now: Date) -> GoCall {
        if dangerousNow && safeWindow == nil { return .danger }
        if let window = safeWindow, window.start.addingTimeInterval(-20 * 60) <= now && window.end >= now && window.score >= 68 {
            return dangerousNow ? .goLater : .goNow
        }
        if safeWindow != nil || peak >= 62 { return .goLater }
        if dangerousNow { return .danger }
        return .skip
    }

    private static func headlineText(call: GoCall, species: String, method: String, window: AttackWindow?, dangerousNow: Bool) -> String {
        let named = species != TackleBook.missingSpecies
        switch call {
        case .danger:
            if named { return "지금은 파도·바람·천둥 때문에 \(species)보다 안전이 먼저입니다." }
            return "지금은 파도·바람·천둥 때문에 안전이 먼저입니다. 기록된 어종 없음"
        case .goNow:
            if !named { return "기록된 어종 없음" }
            return method.isEmpty ? "지금 \(species)" : "지금 \(species), \(method)"
        case .goLater:
            if let window {
                return named ? "\(FieldFormat.clock(window.start))부터 \(species)" : "\(FieldFormat.clock(window.start))부터. 기록된 어종 없음"
            }
            if !named { return "기록된 어종 없음" }
            return dangerousNow ? "지금은 위험하고, 조건이 가라앉은 뒤에만 가능합니다." : "오늘 \(species) 조건이 애매합니다."
        case .skip:
            if named { return "오늘 이 자리는 \(species) 기준으로도 점수가 낮습니다." }
            return "오늘 이 자리는 조건 점수가 낮습니다. 기록된 어종 없음"
        }
    }

    private static func summaryText(point: FishingPoint, species: String, call: GoCall, window: AttackWindow?, peak: Int) -> String {
        let place = point.place.title
        if species == TackleBook.missingSpecies {
            return "\(point.name)(\(place))은 기록된 어종이 없습니다. 조건 점수는 \(peak)점입니다. \(call.title)."
        }
        if let window {
            return "\(point.name)(\(place))의 출처에 적힌 어종은 \(species)입니다. \(FieldFormat.dayClock(window.start))~\(FieldFormat.clock(window.end)) 조건 점수는 \(peak)점입니다."
        }
        return "\(point.name)의 출처에 적힌 어종은 \(species)입니다. 조건 점수는 \(peak)점입니다. \(call.title)."
    }

    private static func nowLine(conditions: ConditionPack, moon: MoonInfo, now: Date) -> String {
        guard let hour = hour(near: now, in: conditions) else { return "현재 조건 자료를 아직 못 받았습니다." }
        let water = hour.seaC ?? hour.airC
        let waterLabel = hour.seaC == nil ? "기온" : "수온"
        var parts = [
            "\(waterLabel) \(FieldFormat.temp(water))",
            hour.tide.title,
            "바람 \(FieldFormat.wind(hour.windMs)) \(FieldFormat.direction(hour.windDeg))",
        ]
        if conditions.usedSea {
            parts.append("파도 \(FieldFormat.meters(hour.waveM))")
            if let range = hour.tideRangeM {
                parts.append(String(format: "조차 약 %.1fm", range))
            }
        }
        parts.append("\(moon.name) · \(moon.tideName)")
        return parts.joined(separator: " · ")
    }

    private static func scriptText(
        point: FishingPoint,
        call: GoCall,
        headline: String,
        nowLine: String,
        windows: [AttackWindow],
        tackle: TacklePlan,
        alternateNote: String?,
        risks: [String],
        moon: MoonInfo
    ) -> String {
        var lines: [String] = []
        lines.append("결론: \(call.title). \(headline)")
        lines.append("지금 조건: \(nowLine)")
        if let window = windows.first {
            let reason = window.reasons.joined(separator: ", ")
            lines.append("공략 시간: \(FieldFormat.dayClock(window.start)) ~ \(FieldFormat.clock(window.end)). \(reason)")
        }
        if windows.count > 1 {
            let more = windows.dropFirst().map { "\(FieldFormat.clock($0.start))~\(FieldFormat.clock($0.end)) \($0.score)점" }.joined(separator: ", ")
            lines.append("다음 후보: \(more)")
        }
        if tackle.method.isEmpty {
            lines.append("대상: \(tackle.species)")
            if !tackle.summary.isEmpty { lines.append(tackle.summary) }
        } else {
            lines.append("대상: \(tackle.species). 방법: \(tackle.method).")
            lines.append("이유: \(tackle.why)")
            lines.append("가방에 넣을 것: \(tackle.rod). \(tackle.reel). 원줄 \(tackle.mainLine). \(tackle.leader)")
            lines.append("바늘·루어: \(tackle.terminal)")
            lines.append("미끼: \(tackle.bait)")
            if tackle.chum != "없음" { lines.append("밑밥: \(tackle.chum)") }
            lines.append("채비: \(tackle.rig) \(tackle.depth)")
            lines.append("입질: \(tackle.bite)")
            if !tackle.adjustments.isEmpty {
                lines.append("오늘 보정: \(tackle.adjustments.joined(separator: " "))")
            }
            for (index, step) in tackle.steps.enumerated() {
                lines.append("\(index + 1). \(step)")
            }
        }
        if let alternateNote { lines.append(alternateNote) }
        if !risks.isEmpty { lines.append("주의: \(risks.joined(separator: " "))") }
        lines.append("달 기준은 \(moon.name)이라 대략값입니다. 물때 시각은 바다 높이 모델 기준이며 10~30분 차이 날 수 있습니다.")
        return lines.joined(separator: "\n")
    }

    private static func context(from pack: ConditionPack, now: Date, stained: Bool, point: FishingPoint) -> FieldContext {
        let hour = hour(near: now, in: pack)
        return FieldContext(
            windMs: hour?.windMs,
            waveM: hour?.waveM,
            tide: hour?.tide ?? .unknown,
            tideRangeM: hour?.tideRangeM,
            stained: stained,
            night: hour.map { isNight($0.time, pack: pack) } ?? false,
            waterC: point.measuredTempC ?? hour?.seaC ?? hour?.airC
        )
    }

    private static func hour(near now: Date, in pack: ConditionPack) -> HourCondition? {
        pack.hours.min {
            abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
        }
    }

    private static func recentRain(_ pack: ConditionPack, now: Date) -> Double {
        pack.hours.filter {
            let gap = now.timeIntervalSince($0.time)
            return gap >= 0 && gap <= 6 * 3600
        }.reduce(0) { $0 + ($1.rainMm ?? 0) }
    }

    private static func pressureTrend(at time: Date, pack: ConditionPack) -> Double? {
        guard let now = pack.hours.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }),
              let nowP = now.pressureHpa,
              let before = pack.hours.min(by: {
                  abs($0.time.timeIntervalSince(time.addingTimeInterval(-6 * 3600))) < abs($1.time.timeIntervalSince(time.addingTimeInterval(-6 * 3600)))
              }),
              let beforeP = before.pressureHpa else { return nil }
        return nowP - beforeP
    }

    private static func isNight(_ date: Date, pack: ConditionPack) -> Bool {
        guard let sunrise = pack.sunrise, let sunset = pack.sunset else {
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 6 || hour >= 19
        }
        let cal = Calendar.current
        let rise = cal.date(bySettingHour: cal.component(.hour, from: sunrise), minute: cal.component(.minute, from: sunrise), second: 0, of: date) ?? sunrise
        let set = cal.date(bySettingHour: cal.component(.hour, from: sunset), minute: cal.component(.minute, from: sunset), second: 0, of: date) ?? sunset
        return date < rise || date > set
    }

    private static func isDawnDusk(_ date: Date, pack: ConditionPack) -> Bool {
        guard let sunrise = pack.sunrise, let sunset = pack.sunset else { return false }
        let cal = Calendar.current
        func sameDay(_ marker: Date) -> Date {
            cal.date(bySettingHour: cal.component(.hour, from: marker), minute: cal.component(.minute, from: marker), second: 0, of: date) ?? marker
        }
        let rise = sameDay(sunrise)
        let set = sameDay(sunset)
        let window: TimeInterval = 90 * 60
        return abs(date.timeIntervalSince(rise)) <= window || abs(date.timeIntervalSince(set)) <= window
    }

    private static func isDanger(_ hour: HourCondition?, sea: Bool) -> Bool {
        guard let hour else { return false }
        let code = hour.weatherCode ?? 0
        if code >= 95 { return true }
        if (hour.windMs ?? 0) >= 12 { return true }
        if sea && (hour.waveM ?? 0) >= 1.8 { return true }
        return false
    }

    private static func windowIsDanger(_ window: AttackWindow, conditions: ConditionPack) -> Bool {
        conditions.hours.contains {
            $0.time >= window.start && $0.time < window.end && isDanger($0, sea: conditions.usedSea)
        }
    }

    private static func riskLines(conditions: ConditionPack, now: Date, usedSea: Bool) -> [String] {
        var lines: [String] = []
        if let hour = hour(near: now, in: conditions) {
            if (hour.windMs ?? 0) >= 8 {
                lines.append("바람이 \(FieldFormat.wind(hour.windMs))입니다. 발밑과 파도를 먼저 보세요.")
            }
            if usedSea, (hour.waveM ?? 0) >= 1.2 {
                lines.append("파고가 \(FieldFormat.meters(hour.waveM))입니다. 방파제 월파면 들어가지 마세요.")
            }
            if (hour.weatherCode ?? 0) >= 95 {
                lines.append("천둥 예보가 있습니다. 낚싯대는 피뢰침이 됩니다.")
            }
        }
        if !usedSea {
            lines.append("이 자리는 바다 칸과 멀어 물때 대신 기온·시간·기압을 봤습니다.")
        } else {
            lines.append("물때 높이는 바다 모델 값입니다. 서해는 실제 조차가 더 클 수 있으니 들물·날물 시각을 우선 보세요.")
        }
        return lines
    }

    /// 이미 다루는 어종만 조건표의 범위와 지금 값을 같이 적습니다. 표에 없는 숫자는 만들지 않습니다.
    static func conditionLines(names: [String], hour: HourCondition?, sea: Bool) -> [String] {
        var lines: [String] = []
        for name in names {
            guard let rule = catalog.first(where: { $0.name == name }) else {
                lines.append("\(name): 이 앱의 조건표에 범위가 없어 수치를 만들지 않습니다.")
                continue
            }
            lines.append(contentsOf: comparisonLines(rule: rule, hour: hour, sea: sea))
        }
        return lines
    }

    private static func tidePreference(_ rule: SpeciesRule) -> String {
        var parts: [String] = []
        if rule.flood { parts.append("들물") }
        if rule.ebb { parts.append("날물") }
        if rule.slack { parts.append("만조·간조") }
        if parts.isEmpty { return "조건표에 물때 선호가 없음" }
        return parts.joined(separator: "·") + "이 맞음"
    }

    /// 조건표에 이미 있는 범위와, 그 시각에 받은 값만 적습니다.
    private static func comparisonLines(rule: SpeciesRule, hour: HourCondition?, sea: Bool) -> [String] {
        let tempSpan = String(format: "잘 맞는 범위 %.0f~%.0f도, 가능한 범위 %.0f~%.0f도", rule.bestMin, rule.bestMax, rule.tempMin, rule.tempMax)
        var lines: [String] = []
        let water = hour.flatMap { $0.seaC ?? $0.airC }
        let waterName = hour?.seaC != nil ? "수온" : "기온"
        if let water {
            let judge: String
            if water >= rule.bestMin && water <= rule.bestMax {
                judge = "잘 맞는 범위 안"
            } else if water >= rule.tempMin && water <= rule.tempMax {
                judge = "가능한 범위 안"
            } else {
                judge = "가능한 범위 밖"
            }
            lines.append(String(format: "%@ %@: 지금 %.0f도. %@. 지금은 %@", rule.name, waterName, water, tempSpan, judge))
        } else {
            lines.append("\(rule.name) 수온: 지금 값 없음. \(tempSpan).")
        }
        if let wind = hour?.windMs {
            let judge = wind > rule.maxWind ? "기준보다 셈" : "기준 안"
            lines.append(String(format: "%@ 바람: 지금 %.0fm/s. 이 어종 기준은 %.0fm/s 이하. 지금은 %@", rule.name, wind, rule.maxWind, judge))
        } else {
            lines.append(String(format: "%@ 바람: 지금 값 없음. 이 어종 기준은 %.0fm/s 이하", rule.name, rule.maxWind))
        }
        if rule.water == .sea {
            if let wave = hour?.waveM {
                let judge = wave > rule.maxWave ? "기준보다 큼" : "기준 안"
                lines.append(String(format: "%@ 파도: 지금 %.1fm. 이 어종 기준은 %.1fm 이하. 지금은 %@", rule.name, wave, rule.maxWave, judge))
            } else if sea {
                lines.append(String(format: "%@ 파도: 지금 값 없음. 이 어종 기준은 %.1fm 이하", rule.name, rule.maxWave))
            }
            let liked = tidePreference(rule)
            if let tide = hour?.tide, tide != .unknown {
                let fits: Bool
                switch tide {
                case .flood: fits = rule.flood
                case .ebb: fits = rule.ebb
                case .high, .low: fits = rule.slack
                case .unknown: fits = false
                }
                let judge = fits ? "맞음" : "이 어종의 물때와 다름"
                lines.append("\(rule.name) 물때: 지금 \(tide.title). 이 어종은 \(liked). 지금은 \(judge)")
            } else {
                lines.append("\(rule.name) 물때: 지금 값 없음. 이 어종은 \(liked)")
            }
        }
        return lines
    }

    /// 고른 시간 안의 한 시간마다, 조건표에서 가장 잘 맞는 생물을 고릅니다.
    /// 바람·파도·천둥으로 빠지는 시간은 dangerous 로 표시하고 점수는 0입니다.
    static func hourJudgements(
        point: FishingPoint,
        conditions: ConditionPack,
        moon: MoonInfo,
        preferred: [String],
        speciesAllow: [String]?,
        from: Date,
        to: Date
    ) -> [HourJudgement] {
        var rules = filteredRules(point: point, conditions: conditions, preferred: preferred)
        if let speciesAllow {
            let allow = Set(speciesAllow)
            rules = rules.filter { allow.contains($0.name) }
        } else {
            let recorded = TackleBook.recordedNames(point: point)
            let matched = rules.filter { recorded.contains($0.name) }
            if !matched.isEmpty { rules = matched }
        }
        guard !rules.isEmpty else { return [] }
        let stained = recentRain(conditions, now: from) >= 4
        var rows: [HourJudgement] = []
        for hour in conditions.hours where hour.time >= from && hour.time < to {
            var bestScore = -1
            var bestRule = rules[0]
            var bestReasons: [String] = []
            for rule in rules {
                let danger = isDanger(hour, sea: conditions.usedSea && rule.water == .sea)
                if danger { continue }
                let result = scoreHour(rule: rule, hour: hour, pack: conditions, moon: moon, point: point, stained: stained)
                if result.0 > bestScore {
                    bestScore = result.0
                    bestRule = rule
                    bestReasons = result.1
                }
            }
            if bestScore < 0 {
                rows.append(HourJudgement(
                    time: hour.time,
                    score: 0,
                    species: rules[0].name,
                    reasons: ["이 시간은 바람·파도·천둥 때문에 제외"],
                    dangerous: true
                ))
            } else {
                rows.append(HourJudgement(
                    time: hour.time,
                    score: bestScore,
                    species: bestRule.name,
                    reasons: bestReasons,
                    dangerous: false
                ))
            }
        }
        return rows
    }

    static func isNightHour(_ date: Date, pack: ConditionPack) -> Bool {
        isNight(date, pack: pack)
    }

    private static let catalog: [SpeciesRule] = [
        SpeciesRule(name: "감성돔", water: .sea, places: [.rock, .pier, .harbor], months: [1, 2, 3, 4, 9, 10, 11, 12], tempMin: 9, tempMax: 20, bestMin: 12, bestMax: 17, flood: true, ebb: true, slack: false, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 9, maxWave: 1.3),
        SpeciesRule(name: "벵에돔", water: .sea, places: [.rock], months: [5, 6, 7, 8, 9, 10, 11], tempMin: 16, tempMax: 26, bestMin: 18, bestMax: 23, flood: true, ebb: false, slack: false, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 7, maxWave: 1.1),
        SpeciesRule(name: "농어", water: .sea, places: [.pier, .harbor, .beach, .rock], months: [4, 5, 6, 9, 10, 11], tempMin: 12, tempMax: 23, bestMin: 15, bestMax: 21, flood: true, ebb: false, slack: false, prefersNight: true, prefersDawn: true, dayOk: false, maxWind: 9, maxWave: 1.2),
        SpeciesRule(name: "광어", water: .sea, places: [.beach, .pier, .boat], months: [4, 5, 6, 9, 10, 11, 12], tempMin: 11, tempMax: 22, bestMin: 14, bestMax: 19, flood: false, ebb: true, slack: true, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 9, maxWave: 1.3),
        SpeciesRule(name: "우럭", water: .sea, places: [.pier, .harbor, .rock, .boat], months: Set(1...12), tempMin: 8, tempMax: 22, bestMin: 12, bestMax: 17, flood: false, ebb: true, slack: true, prefersNight: false, prefersDawn: false, dayOk: true, maxWind: 10, maxWave: 1.4),
        SpeciesRule(name: "볼락", water: .sea, places: [.pier, .rock, .harbor], months: [1, 2, 3, 4, 10, 11, 12], tempMin: 7, tempMax: 17, bestMin: 10, bestMax: 15, flood: true, ebb: true, slack: false, prefersNight: true, prefersDawn: false, dayOk: false, maxWind: 8, maxWave: 1.1),
        SpeciesRule(name: "무늬오징어", water: .sea, places: [.rock, .pier, .harbor], months: [6, 7, 8, 9, 10, 11, 12], tempMin: 14, tempMax: 24, bestMin: 16, bestMax: 22, flood: true, ebb: true, slack: false, prefersNight: true, prefersDawn: true, dayOk: true, maxWind: 8, maxWave: 1.2),
        SpeciesRule(name: "갑오징어", water: .sea, places: [.harbor, .beach, .pier], months: [9, 10, 11, 12], tempMin: 13, tempMax: 23, bestMin: 15, bestMax: 21, flood: true, ebb: false, slack: true, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 8, maxWave: 1.1),
        SpeciesRule(name: "주꾸미", water: .sea, places: [.pier, .harbor, .boat], months: [8, 9, 10, 11, 12], tempMin: 12, tempMax: 23, bestMin: 15, bestMax: 21, flood: false, ebb: true, slack: true, prefersNight: false, prefersDawn: false, dayOk: true, maxWind: 9, maxWave: 1.2),
        SpeciesRule(name: "전갱이", water: .sea, places: [.pier, .harbor], months: [6, 7, 8, 9, 10, 11], tempMin: 16, tempMax: 27, bestMin: 18, bestMax: 24, flood: true, ebb: true, slack: false, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 8, maxWave: 1.1),
        SpeciesRule(name: "숭어", water: .sea, places: [.harbor, .beach, .pier], months: [3, 4, 5, 6, 9, 10, 11], tempMin: 12, tempMax: 24, bestMin: 15, bestMax: 21, flood: true, ebb: false, slack: false, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 7, maxWave: 1.0),
        SpeciesRule(name: "붕장어", water: .sea, places: [.beach, .harbor, .pier], months: [6, 7, 8, 9, 10], tempMin: 18, tempMax: 28, bestMin: 20, bestMax: 25, flood: false, ebb: true, slack: true, prefersNight: true, prefersDawn: false, dayOk: false, maxWind: 8, maxWave: 1.2),
        SpeciesRule(name: "붕어", water: .fresh, places: [.freshwater, .custom], months: Set(1...12), tempMin: 10, tempMax: 30, bestMin: 17, bestMax: 25, flood: false, ebb: false, slack: true, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 8, maxWave: 9),
        SpeciesRule(name: "배스", water: .fresh, places: [.freshwater, .custom], months: Set(1...12), tempMin: 8, tempMax: 28, bestMin: 14, bestMax: 22, flood: false, ebb: false, slack: true, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 9, maxWave: 9),
        SpeciesRule(name: "쏘가리", water: .fresh, places: [.freshwater, .custom], months: [4, 5, 6, 7, 8, 9, 10], tempMin: 12, tempMax: 26, bestMin: 16, bestMax: 22, flood: false, ebb: false, slack: false, prefersNight: false, prefersDawn: true, dayOk: true, maxWind: 6, maxWave: 9),
    ]
}

enum FieldFormat {
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dayClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date)
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "모름" }
        return String(format: "%.0f도", value)
    }

    static func meters(_ value: Double?) -> String {
        guard let value else { return "모름" }
        return String(format: "%.1fm", value)
    }

    static func wind(_ value: Double?) -> String {
        guard let value else { return "모름" }
        return String(format: "%.0fm/s", value)
    }

    static func direction(_ degrees: Double?) -> String {
        guard let degrees else { return "" }
        let names = ["북", "북북동", "북동", "동북동", "동", "동남동", "남동", "남남동", "남", "남남서", "남서", "서남서", "서", "서북서", "북서", "북북서"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return names[index]
    }

    static func distance(_ kilometers: Double?) -> String {
        guard let kilometers else { return "" }
        if kilometers < 1 { return String(format: "%.0fm", kilometers * 1000) }
        return String(format: "%.1fkm", kilometers)
    }

    static func sky(_ code: Int?) -> String {
        guard let code else { return "모름" }
        switch code {
        case 0: return "맑음"
        case 1: return "대체로 맑음"
        case 2: return "조금 흐림"
        case 3: return "흐림"
        case 45, 48: return "안개"
        case 51, 53, 55, 56, 57: return "이슬비"
        case 61, 63, 65, 66, 67: return "비"
        case 71, 73, 75, 77: return "눈"
        case 80, 81, 82: return "소나기"
        case 85, 86: return "눈 소나기"
        case 95, 96, 99: return "천둥"
        default: return "날씨 코드 \(code)"
        }
    }

    static func money(_ won: Int?) -> String {
        guard let won else { return "비용 모름" }
        if won <= 0 { return "약 1천 원 미만" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let text = formatter.string(from: NSNumber(value: won)) ?? "\(won)"
        return "약 \(text)원"
    }
}
