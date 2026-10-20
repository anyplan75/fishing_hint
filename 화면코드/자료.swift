import Foundation

// 앱 전체가 같이 쓰는 자료 모양입니다.
// 지도, 날씨, 채비, 저장 파일이 모두 이 구조를 기준으로 이야기합니다.

enum WaterKind: String, Codable, CaseIterable, Identifiable {
    case sea
    case fresh
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sea: return "바다"
        case .fresh: return "민물"
        case .unknown: return "아직 모름"
        }
    }
}

enum PlaceKind: String, Codable, CaseIterable, Identifiable {
    case pier
    case rock
    case beach
    case harbor
    case freshwater
    case boat
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pier: return "방파제·잔교"
        case .rock: return "갯바위"
        case .beach: return "백사장"
        case .harbor: return "항·포구"
        case .freshwater: return "민물 자리"
        case .boat: return "선상"
        case .custom: return "내가 찍은 자리"
        }
    }
}

enum TidePhase: String, Codable {
    case flood
    case ebb
    case high
    case low
    case unknown

    var title: String {
        switch self {
        case .flood: return "들물"
        case .ebb: return "날물"
        case .high: return "만조"
        case .low: return "간조"
        case .unknown: return "물때 없음"
        }
    }
}

enum GoCall: String, Codable {
    case goNow
    case goLater
    case skip
    case danger

    var title: String {
        switch self {
        case .goNow: return "지금 출발"
        case .goLater: return "시간 맞춰 가라"
        case .skip: return "오늘은 쉬어라"
        case .danger: return "오늘은 나가지 마라"
        }
    }
}

struct FishingPoint: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var place: PlaceKind
    var water: WaterKind
    /// 주변, 내포인트, 찍은자리 중 하나입니다.
    var source: String
    var bottom: String
    var targetMemo: String
    var measuredTempC: Double?
    var memo: String

    var isMine: Bool { source == "내포인트" }
}

struct SavedRegion: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusKm: Double
}

struct HourCondition: Identifiable {
    var id: TimeInterval { time.timeIntervalSince1970 }
    var time: Date
    var airC: Double?
    var seaC: Double?
    var windMs: Double?
    var windDeg: Double?
    var pressureHpa: Double?
    var rainMm: Double?
    var cloud: Double?
    var weatherCode: Int?
    var waveM: Double?
    var seaLevelM: Double?
    var tide: TidePhase
    /// 오늘 곡선에서 읽은 조차(가장 높은 물과 가장 낮은 물의 차이)입니다.
    var tideRangeM: Double?
}

struct ConditionPack {
    var hours: [HourCondition]
    var sunrise: Date?
    var sunset: Date?
    /// 바다 칸이 요청한 자리에서 얼마나 떨어져 있는지입니다.
    var seaCellDistanceKm: Double?
    var usedSea: Bool
    var fetchedAt: Date
    var note: String
}

struct AttackWindow: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var score: Int
    var species: String
    var reasons: [String]
}

struct FieldContext {
    var windMs: Double?
    var waveM: Double?
    var tide: TidePhase
    var tideRangeM: Double?
    var stained: Bool
    var night: Bool
    var waterC: Double?
}

struct TacklePlan: Identifiable {
    var id: String
    var species: String
    var method: String
    var summary: String
    var why: String
    var rod: String
    var reel: String
    var mainLine: String
    var leader: String
    var terminal: String
    var bait: String
    var chum: String
    var rig: String
    var depth: String
    var bite: String
    var steps: [String]
    var bag: [String]
    var avoid: [String]
    var adjustments: [String]
}

struct PointBriefing: Identifiable {
    var id: String { point.id }
    var point: FishingPoint
    var distanceKm: Double?
    var call: GoCall
    var score: Int
    var headline: String
    var summary: String
    var nowLine: String
    var windows: [AttackWindow]
    var hourScores: [Int]
    var tackle: TacklePlan
    var alternate: TacklePlan?
    var alternateNote: String?
    var risks: [String]
    var script: String
    var aiScript: String?
    var conditions: ConditionPack
}

enum RecommendKind: String {
    case plan
    case now
    case shore
    case skin

    var title: String {
        switch self {
        case .plan: return "낚시 계획"
        case .now: return "바로가자"
        case .shore: return "갯가 해루질"
        case .skin: return "수중 스킨해루질"
        }
    }
}

enum RecommendScope {
    case here
    case saved
}

struct SpotFacts {
    var weather: String
    var wind: String
    var pressure: String
    var rain: String
    var water: String
    var wave: String
    var seaLevel: String
    var tide: String
    var moon: String
    var place: String
}

struct SpotPick: Identifiable {
    var id: String
    var kind: RecommendKind
    var point: FishingPoint
    var when: Date
    var successRate: Int
    var distanceKm: Double?
    var costWon: Int?
    var species: String
    var reason: String
    var whyLines: [String]
    var facts: SpotFacts
    var risks: [String]
    var publicSummary: String
    var publicWarnings: [String]
    var factScript: String
    var aiReason: String?
    /// 그 자리에 붙은 공식 바다낚시지수입니다. 가까운 지수가 없으면 "지수 없음"입니다.
    var indexLine: String
}

/// 지도나 추천에서 자리를 누른 뒤, 이름을 물어 저장할 때 쓰는 묶음입니다.
struct SavePrompt: Identifiable {
    let id = UUID()
    var point: FishingPoint
}

struct DiskBox: Codable {
    var myPoints: [FishingPoint]
    var region: SavedRegion?
    var radiusKm: Double
    var preferSpecies: [String]
    var useMyLocation: Bool
    var lastLat: Double?
    var lastLon: Double?
}

enum Geo {
    /// 두 지점 사이의 거리를 킬로미터로 계산합니다.
    static func kilometers(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let earth = 6371.0
        let dLat = (bLat - aLat) * .pi / 180
        let dLon = (bLon - aLon) * .pi / 180
        let lat1 = aLat * .pi / 180
        let lat2 = bLat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }
}
