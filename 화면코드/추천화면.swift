import SwiftUI

// 낚시 계획, 바로가자, 해루질 화면입니다.
// 낚시는 주간·야간을 고르지 않고, 해루질만 주간과 야간을 나눕니다.

struct RecommendScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode = 0
    @State private var day = Date()
    @State private var startHour = 0
    @State private var endHour = 24
    @State private var scopeHere = true
    @State private var gleanNight = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("추천")
                    .font(.largeTitle.weight(.bold))
                HStack(spacing: 8) {
                    modeChip("낚시계획", tag: 0, fill: FieldColor.good)
                    modeChip("바로가자", tag: 1, fill: FieldColor.wait)
                    modeChip("해루질", tag: 2, fill: FieldColor.glean)
                }

                switch mode {
                case 1: nowPage
                case 2: gleanPage
                default: planPage
                }

                notice
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
        .sheet(isPresented: Binding(
            get: { store.selectedPickId != nil },
            set: { if !$0 { store.selectedPickId = nil } }
        )) {
            if let id = store.selectedPickId {
                PickDetailView(pickId: id)
                    .environmentObject(store)
            }
        }
    }

    private func modeChip(_ title: String, tag: Int, fill: Color) -> some View {
        let on = mode == tag
        return Button {
            mode = tag
        } label: {
            Text(title)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(on ? fill : FieldColor.card)
                .foregroundStyle(on ? FieldColor.ink : fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(fill, lineWidth: 3))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var planPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기준은 내 위치 또는 저장한 지역 한 점입니다. 그 일대 공개 글, 지역 이름으로 찾은 유튜브 공개 영상, 공개 포인트를 읽고, 위치를 정한 자리만 받은 날씨·물때로 최대 10곳을 줄 세웁니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            DatePicker("날짜", selection: $day, displayedComponents: .date)
            Stepper("시작 \(startHour)시", value: $startHour, in: 0...23)
            Stepper("끝 \(endHour)시", value: $endHour, in: 1...24)
            Text(endHour <= startHour ? "끝 시각이 시작보다 이르면 다음 날 그 시각까지 봅니다." : "끝 시각 전까지만 찾습니다. 0시부터 24시면 하루 전체입니다.")
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            scopePicker
            Button(store.recommendBusy ? "계산 중" : "이 일정으로 10곳 찾기") {
                store.recommendPlan(on: day, startHour: startHour, endHour: endHour, scope: scopeHere ? .here : .saved)
            }
            .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
            .disabled(store.recommendBusy)
            Text(store.planMessage)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            if store.planPicks.isEmpty {
                Text("추천 자리가 없으면 위 문장에 이유를 적습니다. 위치를 못 정한 글은 넣지 않습니다.")
                    .font(.subheadline)
            }
            ForEach(store.planPicks) { pick in
                Button { store.selectedPickId = pick.id } label: { PickRow(pick: pick) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var nowPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기준은 현재 위치 한 점입니다. 그 일대 공개 글, 지역 이름으로 찾은 유튜브 공개 영상, 공개 포인트를 읽고, 위치를 정한 자리만 지금부터 6시간의 받은 날씨·물때로 최대 3곳을 줄 세웁니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            Button(store.recommendBusy ? "계산 중" : "지금 3곳 찾기") { store.recommendNow() }
                .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                .disabled(store.recommendBusy)
            Text(store.nowMessage)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
                .lineLimit(store.nowPicks.isEmpty ? 4 : nil)
            ForEach(store.nowPicks) { pick in
                Button { store.selectedPickId = pick.id } label: { PickRow(pick: pick) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var gleanPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("해루질은 낚시 추천과 따로입니다. 주간 해루질과 야간 해루질만 고르세요. 갯가와 수중 스킨을 둘 다 보여 줍니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            Picker("해루질 시간", selection: $gleanNight) {
                Text("주간 해루질").tag(false)
                Text("야간 해루질").tag(true)
            }
            .pickerStyle(.segmented)
            DatePicker("날짜", selection: $day, displayedComponents: .date)
            scopePicker
            Button(store.recommendBusy ? "계산 중" : "해루질 자리 보기") {
                store.recommendGleaning(on: day, night: gleanNight, scope: scopeHere ? .here : .saved)
            }
            .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
            .disabled(store.recommendBusy)
            Text(store.gleanMessage)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            gleanSection("갯가 해루질", picks: store.shorePicks, empty: "갯가 추천이 없습니다. 간조 전후와 조건표가 맞는 자리만 나옵니다.")
            gleanSection("수중 스킨해루질", picks: store.skinPicks, empty: "수중 추천이 없습니다. 맨몸 잠수이며, 파도와 바람이 센 시간은 빼 둡니다.")
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("지역", selection: $scopeHere) {
                Text("내 위치 반경").tag(true)
                Text("저장 지역").tag(false)
            }
            .pickerStyle(.segmented)
            if scopeHere {
                Text("반경 \(Int(store.radiusKm))km. 전국은 찾지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                Slider(value: $store.radiusKm, in: 3...30, step: 1, onEditingChanged: { editing in
                    if !editing { store.keepRadius() }
                })
            } else if let region = store.region {
                Text("\(region.name), 저장할 때 반경 \(Int(region.radiusKm))km")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
            } else {
                Text("저장된 지역이 없습니다. 지도에서 이 지역 저장을 먼저 누르세요.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.wait)
            }
        }
    }

    private var notice: some View {
        FieldCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("숫자 읽는 법")
                    .font(.headline)
                Text("성공률은 조건 적합도로 계산한 예상값입니다. 조과를 보장하지 않습니다.")
                Text("예상 비용은 왕복 거리 ÷ 12km/L × 1,700원/L 을 천 원 단위로 반올림한 이동비입니다. 통행료와 선비는 넣지 않습니다.")
                Text("인공지능 암호가 없으면 이유 문장만 빠지고, 시간·성공률·거리·비용·어종은 그대로입니다.")
            }
            .font(.caption)
            .foregroundStyle(FieldColor.muted)
        }
    }

    private func gleanSection(_ title: String, picks: [SpotPick], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
            if picks.isEmpty {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(FieldColor.muted)
            }
            ForEach(grouped(picks), id: \.0) { species, rows in
                Text(species)
                    .font(.headline)
                    .foregroundStyle(FieldColor.good)
                ForEach(rows) { pick in
                    Button { store.selectedPickId = pick.id } label: { PickRow(pick: pick) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func grouped(_ picks: [SpotPick]) -> [(String, [SpotPick])] {
        var order: [String] = []
        var map: [String: [SpotPick]] = [:]
        for pick in picks {
            if map[pick.species] == nil { order.append(pick.species) }
            map[pick.species, default: []].append(pick)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

struct PickRow: View {
    var pick: SpotPick

    private var placeLine: String {
        switch pick.point.source {
        case "공개글": return "공개 글에서 확인"
        case "유튜브": return "유튜브에서 확인"
        default: return pick.point.place.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(FieldFormat.dayClock(pick.when))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FieldColor.good)
                Spacer()
                Text("성공률 \(pick.successRate)%")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(FieldColor.paper)
            }
            Text(pick.point.name)
                .font(.headline)
                .foregroundStyle(FieldColor.paper)
            Text(pick.species)
                .font(.subheadline)
            HStack {
                Text(FieldFormat.distance(pick.distanceKm))
                Text(FieldFormat.money(pick.costWon))
                Text(placeLine)
            }
            .font(.caption)
            .foregroundStyle(FieldColor.muted)
            Text(pick.reason)
                .font(.caption)
                .foregroundStyle(FieldColor.paper)
                .lineLimit(2)
            Text(pick.publicSummary)
                .font(.caption2)
                .foregroundStyle(pick.publicSummary.contains("없음") ? FieldColor.muted : FieldColor.wait)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldColor.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FieldColor.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PickDetailView: View {
    @EnvironmentObject private var store: AppStore
    var pickId: String

    var body: some View {
        if let pick = store.pick(id: pickId) {
            detail(pick)
        } else {
            Text("이 추천을 찾지 못했습니다.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FieldColor.ink)
                .foregroundStyle(FieldColor.paper)
        }
    }

    private func detail(_ pick: SpotPick) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("닫기") { store.selectedPickId = nil }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
                Text(pick.kind.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FieldColor.sea)
                Text(pick.point.name)
                    .font(.title2.weight(.bold))
                Text(FieldFormat.dayClock(pick.when))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(FieldColor.good)
                Text("성공률 \(pick.successRate)% · \(pick.species)")
                    .font(.title3.weight(.semibold))
                Text("성공률은 이 시각의 조건 적합도입니다. 조과를 보장하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                HStack {
                    Text(FieldFormat.distance(pick.distanceKm))
                    Text(FieldFormat.money(pick.costWon))
                }
                .font(.subheadline)
                Text("예상 비용은 왕복 이동비 대략값입니다. 통행료와 선비는 넣지 않았습니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                Text(pick.reason)

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("왜 이 시간인가")
                            .font(.headline)
                        ForEach(Array(pick.whyLines.enumerated()), id: \.offset) { _, line in
                            Text("· \(line)")
                                .font(.subheadline)
                        }
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("모아 둔 사실")
                            .font(.headline)
                        fact("날씨", pick.facts.weather)
                        fact("바람", pick.facts.wind)
                        fact("기압", pick.facts.pressure)
                        fact("강수", pick.facts.rain)
                        fact("수온", pick.facts.water)
                        fact("파도", pick.facts.wave)
                        fact("해수면", pick.facts.seaLevel)
                        fact("들물·날물", pick.facts.tide)
                        fact("달", pick.facts.moon)
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("지역 특성")
                            .font(.headline)
                        Text(pick.facts.place)
                            .font(.subheadline)
                    }
                }

                if !pick.risks.isEmpty {
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("주의할 점")
                                .font(.headline)
                                .foregroundStyle(FieldColor.bad)
                            ForEach(Array(pick.risks.enumerated()), id: \.offset) { _, line in
                                Text("· \(line)")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("공공자료")
                            .font(.headline)
                        Text(pick.publicSummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FieldColor.wait)
                        ForEach(Array(pick.publicWarnings.enumerated()), id: \.offset) { _, line in
                            Text("· \(line)")
                                .font(.subheadline)
                        }
                        Text("해로드 앱과 안전해 앱은 연결하지 않았습니다. 위 문장에 없는 마을어장이나 사고는 지어내지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(FieldColor.muted)
                    }
                }

                if let ai = pick.aiReason, !ai.isEmpty {
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("인공지능이 다듬은 이유")
                                .font(.headline)
                            Text("숫자와 순위는 위의 계산을 기준으로 합니다. 자료에 없는 사실은 쓰지 말라고 시켜 두었습니다.")
                                .font(.caption)
                                .foregroundStyle(FieldColor.muted)
                            Text(ai)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text("인공지능 문장은 없습니다. 암호가 없거나 아직 다듬기 전이어도 시간, 성공률, 거리, 비용, 어종은 위에서 그대로 보면 됩니다.")
                        .font(.caption)
                        .foregroundStyle(FieldColor.muted)
                }
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }

    private func fact(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(name)
                .font(.caption.weight(.bold))
                .foregroundStyle(FieldColor.sea)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
