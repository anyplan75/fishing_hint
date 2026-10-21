import SwiftUI
import WebKit

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
            Text("중심은 지도에 찍은 자리입니다. 핀이 없으면 현재 위치입니다. 반경은 지도에서 고른 \(Int(store.radiusKm))km와 같습니다. 그 밖은 넣지 않습니다. 그 지명과 주변 지명으로 구글 검색을 하고, 출처에 나온 포인트만 다시 검색합니다. 공개 글, 유튜브, 바다낚시지수, 전국낚시터도 읽습니다. 검색에 없는 자리는 만들지 않습니다. 최대 10곳입니다. 네이버 키가 없으면 네이버는 부르지 않습니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            DatePicker("날짜", selection: $day, displayedComponents: .date)
            Stepper("시작 \(startHour)시", value: $startHour, in: 0...23)
            Stepper("끝 \(endHour)시", value: $endHour, in: 1...24)
            Text(endHour <= startHour ? "끝 시각이 시작보다 이르면 다음 날 그 시각까지 봅니다." : "끝 시각 전까지만 찾습니다. 0시부터 24시면 하루 전체입니다.")
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            Text("반경 \(Int(store.radiusKm))km. 지도와 같은 값입니다.")
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            Slider(value: $store.radiusKm, in: 3...30, step: 1, onEditingChanged: { editing in
                if !editing { store.keepRadius() }
            })
            Button(store.recommendBusy ? "계산 중" : "이 일정으로 10곳 찾기") {
                store.recommendPlan(on: day, startHour: startHour, endHour: endHour, scope: .here)
            }
            .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
            .disabled(store.recommendBusy)
            Text(store.planMessage)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            if !store.googleSuggestHtml.isEmpty {
                SearchSuggestBox(html: store.googleSuggestHtml)
            }
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
            Text("중심은 지도에 찍은 자리입니다. 핀이 없으면 현재 위치입니다. 반경은 지도에서 고른 \(Int(store.radiusKm))km와 같습니다. 그 밖은 넣지 않습니다. 그 지명과 주변 지명으로 구글 검색을 하고, 출처에 나온 포인트만 다시 검색합니다. 공개 글, 유튜브, 바다낚시지수, 전국낚시터도 읽습니다. 검색에 없는 자리는 만들지 않습니다. 최대 3곳입니다. 네이버 키가 없으면 네이버는 부르지 않습니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)
            Button(store.recommendBusy ? "계산 중" : "지금 3곳 찾기") { store.recommendNow() }
                .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                .disabled(store.recommendBusy)
            Text(store.nowMessage)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
                .lineLimit(store.nowPicks.isEmpty ? 4 : nil)
            if !store.googleSuggestHtml.isEmpty {
                SearchSuggestBox(html: store.googleSuggestHtml)
            }
            ForEach(store.nowPicks) { pick in
                Button { store.selectedPickId = pick.id } label: { PickRow(pick: pick) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var gleanPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("해루질은 낚시 추천과 따로입니다. 주간 해루질과 야간 해루질만 고르세요. 갯가는 주변 공개 자리이고, 수중 스킨은 스킨스쿠버지수에 있는 포인트만 보여 줍니다.")
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
            gleanSection("수중 스킨해루질", picks: store.skinPicks, empty: "수중 추천이 없습니다. 스킨스쿠버지수에서 읽은 포인트만 나옵니다. 키가 거절되면 위 문장에 짧은 이유만 적습니다.")
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
                Text("성공률은 그 시간의 조건 적합도입니다. 카드에는 바다낚시지수를 같이 보여 줍니다. 가까운 지수가 없으면 지수 없음이라고 적고, 성공률은 그대로 보여 줍니다. 조과를 보장하지 않습니다.")
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
        case "바다낚시지수": return "바다낚시지수"
        case "낚시터표준": return "전국낚시터"
        case "스킨스쿠버": return "스킨스쿠버지수"
        case "구글": return "구글 검색에서 확인"
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
            Text(pick.indexLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FieldColor.wait)
                .lineLimit(3)
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
    @State private var naming = false

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
                HStack {
                    Button("닫기") { store.selectedPickId = nil }
                        .buttonStyle(FieldButton(fill: FieldColor.card2))
                    Button("이름 정하고 저장") { naming = true }
                        .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                }
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
                Text(pick.indexLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FieldColor.wait)
                Text("성공률은 이 시각의 조건 적합도입니다. 바다낚시지수는 이 자리에 붙은 공식 지점의 지수와 조황 여건입니다. 조과를 보장하지 않습니다.")
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
        .sheet(isPresented: $naming) {
            NameSaveSheet(point: pick.point)
        }
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

/// 구글이 준 검색 제안 HTML을 고치지 않고 결과 위에 작게 보여 줍니다.
struct SearchSuggestBox: View {
    var html: String

    var body: some View {
        SearchSuggestWeb(html: html)
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FieldColor.line, lineWidth: 1))
    }
}

#if os(iOS)
private struct SearchSuggestWeb: UIViewRepresentable {
    var html: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.scrollView.isScrollEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.shown != html else { return }
        context.coordinator.shown = html
        view.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    }

    func makeCoordinator() -> Holder { Holder() }

    final class Holder { var shown = "" }
}
#else
private struct SearchSuggestWeb: NSViewRepresentable {
    var html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.shown != html else { return }
        context.coordinator.shown = html
        view.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    }

    func makeCoordinator() -> Holder { Holder() }

    final class Holder { var shown = "" }
}
#endif
