import SwiftUI

// 한 자리의 출발 판단, 공략 시간, 오늘 채비, 가방 목록입니다.

struct PointDetailView: View {
    @EnvironmentObject private var store: AppStore
    var pointId: String
    @State private var checked: Set<Int> = []
    @State private var editing = false
    @State private var naming = false

    var body: some View {
        if let briefing = store.briefings[pointId] {
            detail(briefing)
        } else if let reason = store.detailMiss[pointId] {
            missed(reason)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("이 자리의 물때와 수온을 계산하는 중입니다.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FieldColor.ink)
            .foregroundStyle(FieldColor.paper)
        }
    }

    private func missed(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Text(reason)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button("닫기") { store.selectedPointId = nil }
                .buttonStyle(FieldButton(fill: FieldColor.card2))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }

    private func detail(_ briefing: PointBriefing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("닫기") { store.selectedPointId = nil }
                        .buttonStyle(FieldButton(fill: FieldColor.card2))
                    Spacer()
                    if briefing.point.isMine {
                        Button("자리 수정") { editing = true }
                            .buttonStyle(FieldButton(fill: FieldColor.card2))
                    } else {
                        Button("이름 정하고 저장") { naming = true }
                            .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                    }
                }
                Text(briefing.call.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.call(briefing.call))
                Text(briefing.point.name)
                    .font(.title2.weight(.semibold))
                Text(briefing.summary)
                    .font(.body)
                Text(briefing.nowLine)
                    .font(.subheadline)
                    .foregroundStyle(FieldColor.muted)
                Text(briefing.conditions.note)
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)

                if !briefing.windows.isEmpty {
                    FieldCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("공략 시간")
                                .font(.headline)
                            ForEach(briefing.windows) { window in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(FieldFormat.dayClock(window.start)) – \(FieldFormat.clock(window.end))  ·  \(window.score)점")
                                        .font(.subheadline.weight(.semibold))
                                    Text(window.reasons.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(FieldColor.muted)
                                }
                            }
                        }
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("시간대 점수")
                            .font(.headline)
                        Text("높은 막대가 오늘 그 시간에 조건이 좋은 때입니다. 빨간 막대는 위험해서 뺀 시간입니다.")
                            .font(.caption)
                            .foregroundStyle(FieldColor.muted)
                        ScoreRibbon(
                            scores: Array(briefing.hourScores.prefix(36)),
                            times: briefing.conditions.hours.prefix(36).map(\.time)
                        )
                    }
                }

                if let ai = briefing.aiScript, !ai.isEmpty {
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("인공지능이 다듬은 오늘 순서")
                                .font(.headline)
                            Text("숫자와 채비 규격은 아래 계산표를 기준으로 합니다.")
                                .font(.caption)
                                .foregroundStyle(FieldColor.muted)
                            Text(ai)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }

                tackleBlock(briefing.tackle, title: "오늘 채비")
                if let note = briefing.alternateNote {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(FieldColor.wait)
                }
                if let alternate = briefing.alternate {
                    tackleBlock(alternate, title: "가방에 같이 넣을 예비")
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("가방 체크")
                            .font(.headline)
                        ForEach(Array(briefing.tackle.bag.enumerated()), id: \.offset) { index, item in
                            Button {
                                if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: checked.contains(index) ? "checkmark.square.fill" : "square")
                                    Text(item)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !briefing.risks.isEmpty {
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("나가기 전에")
                                .font(.headline)
                                .foregroundStyle(FieldColor.bad)
                            ForEach(briefing.risks, id: \.self) { risk in
                                Text("· \(risk)")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("계산된 순서 원문")
                            .font(.headline)
                        Text(briefing.script)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(FieldColor.muted)
                    }
                }
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
        .sheet(isPresented: $editing) {
            PointEditSheet(point: briefing.point) { store.updateMine($0) }
        }
        .sheet(isPresented: $naming) {
            NameSaveSheet(point: briefing.point)
        }
    }

    private func tackleBlock(_ plan: TacklePlan, title: String) -> some View {
        FieldCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(plan.species) · \(plan.method)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FieldColor.good)
                Text(plan.summary)
                Text(plan.why)
                    .font(.subheadline)
                    .foregroundStyle(FieldColor.muted)
                spec("낚싯대", plan.rod)
                spec("릴", plan.reel)
                spec("원줄", plan.mainLine)
                spec("목줄", plan.leader)
                spec("바늘·루어", plan.terminal)
                spec("미끼", plan.bait)
                spec("밑밥", plan.chum)
                spec("묶음", plan.rig)
                spec("수심", plan.depth)
                spec("입질", plan.bite)
                if !plan.adjustments.isEmpty {
                    Text("오늘 보정")
                        .font(.subheadline.weight(.bold))
                        .padding(.top, 4)
                    ForEach(plan.adjustments, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                }
                Text("현장 순서")
                    .font(.subheadline.weight(.bold))
                    .padding(.top, 4)
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.subheadline)
                }
                if !plan.avoid.isEmpty {
                    Text("하지 말 것")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FieldColor.bad)
                        .padding(.top, 4)
                    ForEach(plan.avoid, id: \.self) { line in
                        Text("· \(line)").font(.subheadline)
                    }
                }
            }
        }
    }

    private func spec(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption.weight(.bold))
                .foregroundStyle(FieldColor.sea)
            Text(value)
                .font(.subheadline)
        }
    }
}

struct PointEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var point: FishingPoint
    var onSave: (FishingPoint) -> Void
    @State private var tempText = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("이름", text: $point.name)
                Picker("자리", selection: $point.place) {
                    ForEach(PlaceKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("물", selection: $point.water) {
                    ForEach(WaterKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("바닥 (암초, 모래, 뻘, 수초)", text: $point.bottom)
                TextField("노리는 고기", text: $point.targetMemo)
                TextField("내가 잰 수온", text: $tempText)
                TextField("메모 (주차, 진입)", text: $point.memo)
            }
            .navigationTitle("내 포인트")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let trimmed = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        point.name = trimmed
                        if let value = Double(tempText) { point.measuredTempC = value }
                        point.source = "내포인트"
                        onSave(point)
                        dismiss()
                    }
                    .disabled(point.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let temp = point.measuredTempC { tempText = String(format: "%.1f", temp) }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct NameSaveSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var point: FishingPoint
    @State private var name: String
    @FocusState private var focused: Bool

    init(point: FishingPoint) {
        self.point = point
        let preset = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        _name = State(initialValue: preset == "찍은 자리" ? "" : preset)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("이 자리의 이름을 적으세요. 저장하면 내 포인트 목록에 이 이름이 남습니다. 이름을 비우면 저장하지 않습니다.")
                    .font(.subheadline)
                    .foregroundStyle(FieldColor.muted)
                TextField("장소 이름", text: $name)
                    .focused($focused)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { storeName() }
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("이름을 비우면 저장하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(FieldColor.wait)
                }
                Button("저장") { storeName() }
                    .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(16)
            .background(FieldColor.ink)
            .foregroundStyle(FieldColor.paper)
            .navigationTitle("이름 정하고 저장")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { storeName() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func storeName() {
        if store.commitNamedSave(point: point, name: name) {
            dismiss()
        }
    }
}
