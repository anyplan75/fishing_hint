import Foundation

// 달의 모양(삭·보름)과 대략적인 남중 시각을 계산합니다.
// 사리·조금을 가늠하는 데 쓰고, 점수의 주인공은 아닙니다.
// 남중 시각은 대략값이라 20~40분 어긋날 수 있습니다.

struct MoonInfo {
    var ageDays: Double
    var name: String
    var tideName: String
    var isSpring: Bool
    var isNeap: Bool
    var majors: [DateInterval]
    var minors: [DateInterval]
}

enum MoonClock {
    private static let synodic = 29.530588853
    /// 2000년 1월 6일 18:14 UTC는 잘 알려진 삭(신월) 기준입니다.
    private static let reference = Date(timeIntervalSince1970: 947182440)

    static func info(on date: Date, longitude: Double) -> MoonInfo {
        let age = date.timeIntervalSince(reference) / 86_400
        let wrapped = age.truncatingRemainder(dividingBy: synodic)
        let ageDays = wrapped >= 0 ? wrapped : wrapped + synodic
        let name = phaseName(ageDays)
        let spring = isSpring(ageDays)
        let neap = isNeap(ageDays)
        let periods = solunar(on: date, longitude: longitude)
        return MoonInfo(
            ageDays: ageDays,
            name: name,
            tideName: spring ? "사리 근처" : (neap ? "조금 근처" : "중간 물때"),
            isSpring: spring,
            isNeap: neap,
            majors: periods.majors,
            minors: periods.minors
        )
    }

    private static func phaseName(_ age: Double) -> String {
        switch age {
        case ..<1.5, 28.2...: return "삭"
        case ..<6.0: return "초승"
        case ..<9.0: return "상현"
        case ..<13.5: return "상현에서 보름"
        case ..<16.5: return "보름"
        case ..<21.0: return "보름에서 하현"
        case ..<24.0: return "하현"
        default: return "그믐"
        }
    }

    private static func isSpring(_ age: Double) -> Bool {
        age < 2 || (age >= 13.6 && age <= 16.4) || age > 27.8
    }

    private static func isNeap(_ age: Double) -> Bool {
        (age >= 5.6 && age <= 9.2) || (age >= 20.4 && age <= 24.2)
    }

    /// 달의 황경과 항성시를 써서 그날 남중(하늘 한가운데) 시각을 구합니다.
    private static func solunar(on date: Date, longitude: Double) -> (majors: [DateInterval], minors: [DateInterval]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = calendar.startOfDay(for: date)
        let jd = julianDay(start)
        let n = jd - 2_451_545.0
        let L = radians(218.316 + 13.176396 * n)
        let M = radians(134.963 + 13.064993 * n)
        let F = radians(93.272 + 13.229350 * n)
        let lambda = L + radians(6.289 * sin(M))
        let beta = radians(5.128 * sin(F))
        let eps = radians(23.439 - 0.0000004 * n)
        let ra = atan2(sin(lambda) * cos(eps) - tan(beta) * sin(eps), cos(lambda))
        let raDeg = (degrees(ra).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let gmst = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360)
        var ut = (raDeg - (gmst < 0 ? gmst + 360 : gmst) - longitude) / 15.0
        ut = (ut.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)

        let upper = start.addingTimeInterval(ut * 3600)
        let lower = upper.addingTimeInterval(12 * 3600 + 25 * 60)
        let majors = [interval(upper, minutes: 60), interval(lower, minutes: 60)]
        let minors = [
            interval(upper.addingTimeInterval(6 * 3600 + 12 * 60), minutes: 30),
            interval(lower.addingTimeInterval(6 * 3600 + 12 * 60), minutes: 30),
        ]
        return (majors, minors)
    }

    private static func interval(_ center: Date, minutes: Double) -> DateInterval {
        let half = minutes * 60
        return DateInterval(start: center.addingTimeInterval(-half), duration: half * 2)
    }

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
