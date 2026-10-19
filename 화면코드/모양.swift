import SwiftUI

// 현장에서 햇빛을 받아도 점수와 경고가 구분되게 색을 고정합니다.

enum FieldColor {
    static let ink = Color(red: 0.03, green: 0.07, blue: 0.09)
    static let card = Color(red: 0.07, green: 0.14, blue: 0.18)
    static let card2 = Color(red: 0.11, green: 0.20, blue: 0.25)
    static let line = Color(red: 0.22, green: 0.36, blue: 0.40)
    static let paper = Color(red: 0.93, green: 0.95, blue: 0.90)
    static let good = Color(red: 0.84, green: 0.95, blue: 0.36)
    static let wait = Color(red: 0.56, green: 0.83, blue: 1.0)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let sea = Color(red: 0.11, green: 0.55, blue: 0.53)
    static let glean = Color(red: 1.0, green: 0.62, blue: 0.18)
    static let muted = Color(red: 0.62, green: 0.71, blue: 0.74)
}

extension Color {
    static func call(_ call: GoCall) -> Color {
        switch call {
        case .goNow: return FieldColor.good
        case .goLater: return FieldColor.wait
        case .skip: return FieldColor.muted
        case .danger: return FieldColor.bad
        }
    }
}

struct FieldCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FieldColor.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FieldColor.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ScoreRibbon: View {
    var scores: [Int]
    var times: [Date]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(score))
                            .frame(width: 14, height: max(8, CGFloat(score) * 0.42))
                        if index % 3 == 0, times.indices.contains(index) {
                            Text(FieldFormat.clock(times[index]))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(FieldColor.muted)
                        } else {
                            Text(" ")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(_ score: Int) -> Color {
        if score >= 75 { return FieldColor.good }
        if score >= 60 { return FieldColor.wait }
        if score == 0 { return FieldColor.bad.opacity(0.7) }
        return FieldColor.line
    }
}
