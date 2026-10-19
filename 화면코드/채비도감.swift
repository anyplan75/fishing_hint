import SwiftUI

// 고기별 기본 채비입니다. 바람과 조차가 반영된 오늘 채비는 포인트 화면에 나옵니다.

struct TackleLibraryView: View {
    @State private var query = ""
    private var plans: [TacklePlan] { TackleBook.encyclopedia() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("채비도감")
                    .font(.largeTitle.weight(.bold))
                Text("현장에 가기 전에 호수와 묶음을 외우는 장입니다. 오늘 바람과 물때에 맞춘 보정은 지도의 포인트 분석에 있습니다.")
                    .foregroundStyle(FieldColor.muted)
                TextField("고기 이름", text: $query)
                    .textFieldStyle(.roundedBorder)
                ForEach(filtered) { plan in
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.species)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(FieldColor.good)
                            Text(plan.method)
                                .font(.headline)
                            Text(plan.summary)
                            Text(plan.why)
                                .font(.subheadline)
                                .foregroundStyle(FieldColor.muted)
                            line("대", plan.rod)
                            line("릴", plan.reel)
                            line("원줄", plan.mainLine)
                            line("목줄", plan.leader)
                            line("끝채비", plan.terminal)
                            line("미끼", plan.bait)
                            line("수심", plan.depth)
                            line("입질", plan.bite)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }

    private var filtered: [TacklePlan] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return plans }
        return plans.filter { $0.species.contains(text) || $0.method.contains(text) }
    }

    private func line(_ name: String, _ value: String) -> some View {
        Text("\(name): \(value)")
            .font(.subheadline)
    }
}

struct MyPointsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("내 포인트")
                    .font(.largeTitle.weight(.bold))
                Text("내가 찍어서 저장한 자리입니다. 반경 밖이어도 분석 목록에 같이 들어갑니다.")
                    .foregroundStyle(FieldColor.muted)
                if store.myPoints.isEmpty {
                    Text("아직 없습니다. 지도에서 자리를 연 뒤 '내 포인트로 저장'을 누르세요.")
                        .padding(.top, 12)
                }
                ForEach(store.myPoints) { point in
                    FieldCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(point.name).font(.headline)
                            Text("\(point.place.title) · \(point.water.title)")
                                .font(.caption)
                                .foregroundStyle(FieldColor.muted)
                            if !point.targetMemo.isEmpty {
                                Text("노리는 고기 \(point.targetMemo)")
                                    .font(.subheadline)
                            }
                            if !point.memo.isEmpty {
                                Text(point.memo)
                                    .font(.caption)
                                    .foregroundStyle(FieldColor.muted)
                            }
                            HStack {
                                Button("분석") { store.select(point.id) }
                                    .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                                Button("삭제") { store.deleteMine(point) }
                                    .buttonStyle(FieldButton(fill: FieldColor.bad, ink: FieldColor.ink))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("설정")
                    .font(.largeTitle.weight(.bold))
                Text("암호는 이 화면에 넣지 않습니다. 연결만 여기서 봅니다.")
                    .foregroundStyle(FieldColor.muted)

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("연결")
                            .font(.headline)
                        Text(store.mapLink.connected ? "지도 연결됨" : store.mapLink.reason)
                        Text(store.aiLink.connected ? "인공지능 연결됨" : store.aiLink.reason)
                        Text(store.tideLink.connected ? "조석 연결됨" : store.tideLink.reason)
                    }
                    .font(.subheadline)
                }

                Text("노리는 고기")
                    .font(.headline)
                Text(store.preferSpecies.isEmpty ? "비워 두면 자리와 수온에 맞는 고기를 앱이 고릅니다." : "고른 고기만 점수를 매깁니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(TackleBook.speciesOrder, id: \.self) { name in
                        Button(name) { store.toggleSpecies(name) }
                            .buttonStyle(FieldButton(
                                fill: store.preferSpecies.contains(name) ? FieldColor.good : FieldColor.card2,
                                ink: store.preferSpecies.contains(name) ? FieldColor.ink : FieldColor.paper
                            ))
                    }
                }

                FieldCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("분석이 보는 것")
                            .font(.headline)
                        Text("한 시간 단위로 수온, 들물·날물, 바람, 파도, 비, 기압 변화, 해 뜨고 지는 시각, 달의 모양을 점수로 바꿉니다. 천둥, 초속 12m 이상 바람, 파고 1.8m 이상은 점수가 높아도 나가지 말라고 바꿉니다.")
                        Text("물때 높이는 바다 예보 모델입니다. 시각이 공식 조석표와 10~30분 다를 수 있습니다. 조과는 보장하지 않습니다.")
                            .foregroundStyle(FieldColor.muted)
                    }
                    .font(.subheadline)
                }
                Text("바로낚시 0.1.0")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(FieldColor.wait)
            }
            .padding(16)
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }
}
