import SwiftUI

// 낚시글 탭에서만 공개 글을 보여 줍니다. 낚시 계획·바로가자·해루질 화면에는 넣지 않습니다.

@MainActor
final class PublicFishingBoard: ObservableObject {
    static let shared = PublicFishingBoard()

    @Published var notes: [PublicFishingNote] = []
    @Published var lines: [PublicSourceLine] = []
    @Published var busy = false
    @Published var fetchedAt: Date?

    /// 받기가 끝난 뒤 이 시간 안에는 같은 글을 다시 보여 줍니다.
    private let quietSeconds: TimeInterval = 120
    private var inFlight = false
    private var lastAnsweredAt: Date?

    private init() {}

    /// 낚시글 탭을 열 때 부릅니다. 추천 화면에서는 부르지 않습니다.
    func refreshIfNeeded() {
        if inFlight { return }
        if let lastAnsweredAt, Date().timeIntervalSince(lastAnsweredAt) < quietSeconds { return }
        inFlight = true
        busy = true
        Task {
            let bundle = await PublicFishingClient.load()
            notes = bundle.notes
            lines = bundle.lines
            fetchedAt = Date()
            busy = false
            inFlight = false
            lastAnsweredAt = bundle.answered ? Date() : nil
        }
    }
}

struct PublicFishingScreen: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var board = PublicFishingBoard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("낚시글")
                .font(.largeTitle.weight(.bold))
            Text("로그인 없이 열린 글만 모읍니다. 지금 보는 위치 근처만 남기고, 없는 글은 만들지 않습니다.")
                .font(.subheadline)
                .foregroundStyle(FieldColor.muted)

            if let anchor = anchorName {
                Text("\(anchor) 근처 글만 보여 줍니다. 지역을 알 수 없는 글은 빼 둡니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                if nearby.isEmpty {
                    Text(board.busy ? "공개 글을 가져오는 중입니다." : "이 근처의 공개 글이 없습니다. 없는 글은 만들지 않습니다.")
                        .font(.subheadline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(nearby) { note in
                                noteCard(note)
                            }
                        }
                    }
                }
            } else {
                Text(missingPlace)
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
        .onAppear { PublicFishingBoard.shared.refreshIfNeeded() }
    }

    private var nearby: [PublicFishingNote] {
        guard let anchor = anchorName else { return [] }
        return PublicNearby.keep(board.notes, anchor: anchor)
    }

    private var anchorName: String? {
        let raw = store.useMyLocation ? store.regionTitle : (store.region?.name ?? store.regionTitle)
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PublicNearby.canFilter(name) else { return nil }
        return name
    }

    private var missingPlace: String {
        let raw = (store.useMyLocation ? store.regionTitle : (store.region?.name ?? store.regionTitle))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "선택한 지역" {
            return "위치 이름을 아직 모릅니다. 지도에서 내 위치나 저장한 지역을 고르면 그 근처 글만 보여 줍니다."
        }
        return "이 위치 이름을 지역으로 구분하지 못해 근처 글을 보여 주지 않습니다."
    }

    private func noteCard(_ note: PublicFishingNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.sourceName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FieldColor.sea)
                Spacer(minLength: 8)
                Text(note.writtenAt.map { whenText($0, hasClock: note.hasClock) } ?? "시각 없음")
                    .font(.caption2)
                    .foregroundStyle(FieldColor.muted)
            }
            if note.placeLabel.isEmpty == false {
                Text(note.placeLabel)
                    .font(.caption2)
                    .foregroundStyle(FieldColor.muted)
            }
            Text(note.summary)
                .font(.subheadline)
                .foregroundStyle(FieldColor.paper)
                .fixedSize(horizontal: false, vertical: true)
            Link("출처 열기", destination: note.pageURL)
                .font(.caption.weight(.bold))
                .foregroundStyle(FieldColor.good)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldColor.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func whenText(_ date: Date, hasClock: Bool) -> String {
        if hasClock { return FieldFormat.dayClock(date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
