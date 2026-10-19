import SwiftUI

// 추천 화면 아래에 공개 낚시글을 보여 줍니다.
// 앱을 켜거나 이 화면이 나타날 때 최신 공개 글을 다시 받습니다.

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

    /// 앱을 켜거나 낚시 계획·바로가자·해루질이 있는 추천 화면을 열 때 부릅니다.
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

struct RecommendFishingHost: View {
    var body: some View {
        RecommendScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PublicFishingStrip()
            }
            .onAppear { PublicFishingBoard.shared.refreshIfNeeded() }
    }
}

struct PublicFishingStrip: View {
    @ObservedObject private var board = PublicFishingBoard.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("공개 낚시글")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
            }
            Text("로그인 없이 열린 조황·포인트·현장 글입니다. 없는 글은 만들지 않습니다.")
                .font(.caption)
                .foregroundStyle(FieldColor.muted)

            if board.notes.isEmpty {
                Text(board.busy ? "공개 글을 가져오는 중입니다." : "지금 보여줄 공개 글이 없습니다.")
                    .font(.subheadline)
                    .foregroundStyle(FieldColor.paper)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(board.notes) { note in
                            noteCard(note)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if board.lines.isEmpty == false {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(board.lines) { line in
                        Text("\(line.name): \(line.detail)")
                            .font(.caption2)
                            .foregroundStyle(FieldColor.muted)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldColor.card)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(FieldColor.line), alignment: .top)
    }

    private var statusLine: String {
        if board.busy { return "가져오는 중" }
        guard let fetchedAt = board.fetchedAt else { return "아직 안 받음" }
        return "받은 시각 \(whenText(fetchedAt, hasClock: true))"
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
