import Foundation

// 현장에서 바로 쓸 채비 규격입니다.
// 호수와 길이는 한국 바다·민물에서 오래 쓰인 기준이고,
// 바람·조차·물색이 있으면 그 자리에서 한 단계 바꿉니다.

enum TackleBook {
    static let speciesOrder = [
        "감성돔", "벵에돔", "농어", "광어", "우럭", "볼락",
        "무늬오징어", "갑오징어", "주꾸미", "전갱이", "숭어", "붕장어",
        "붕어", "배스", "쏘가리",
    ]

    static func plan(for species: String, context: FieldContext) -> TacklePlan {
        switch species {
        case "감성돔": return gamsung(context)
        case "벵에돔": return benge(context)
        case "농어": return nungeo(context)
        case "광어": return gwang(context)
        case "우럭": return ureok(context)
        case "볼락": return bollak(context)
        case "무늬오징어": return eging(context)
        case "갑오징어": return gap(context)
        case "주꾸미": return jukkumi(context)
        case "전갱이": return jeongang(context)
        case "숭어": return sung(context)
        case "붕장어": return bung(context)
        case "붕어": return bungeo(context)
        case "배스": return bass(context)
        case "쏘가리": return sogari(context)
        default: return gamsung(context)
        }
    }

    static func encyclopedia() -> [TacklePlan] {
        speciesOrder.map { plan(for: $0, context: FieldContext(windMs: nil, waveM: nil, tide: .unknown, tideRangeM: nil, stained: false, night: false, waterC: nil)) }
    }

    private static func seaBag(night: Bool) -> [String] {
        var bag = [
            "구명조끼. 방파제와 갯바위는 선택이 아닙니다.",
            "미끄럼 방지 신발, 플라이어, 수건, 바늘 정리통",
            "여분 목줄 2세트, 바늘 한 통, 도래, 봉돌",
            "식수. 손 씻을 물과 마실 물을 나눕니다.",
        ]
        if night {
            bag.append("헤드랜턴과 여분 전지. 붉은 빛이면 고기 경계가 덜합니다.")
        }
        return bag
    }

    private static func freshBag(night: Bool) -> [String] {
        var bag = ["좌대·방수 매트, 플라이어, 여분 바늘과 봉돌", "모기·풀 벌레 대비, 식수"]
        if night { bag.append("헤드랜턴") }
        return bag
    }

    private static func windHeavy(_ ctx: FieldContext) -> Bool { (ctx.windMs ?? 0) >= 6 }
    private static func tideStrong(_ ctx: FieldContext) -> Bool { (ctx.tideRangeM ?? 0) >= 3.2 }

    private static func gamsung(_ ctx: FieldContext) -> TacklePlan {
        let heavy = windHeavy(ctx) || tideStrong(ctx)
        let floatText = heavy
            ? "구멍찌 2.5호~3호(B 전후). 조류나 바람이 세면 0.5호씩 올립니다."
            : "구멍찌 1.5호~2호. 조류가 약하면 1호까지 내려도 됩니다."
        let leader = ctx.stained
            ? "카본 목줄 2호, 길이 2m. 물색이 탁하면 목줄을 조금 굵고 짧게."
            : "카본 목줄 1.5~1.75호, 길이 2.5~3m."
        var adjustments: [String] = []
        if heavy { adjustments.append("찌를 키웠습니다. 채비가 떠내려가면 한 호수 더 올리지, 원줄을 굵게 하지는 마세요.") }
        if ctx.stained { adjustments.append("비 뒤라 크릴을 으깨 냄새를 내고, 밑밥 점도를 조금 되게 합니다.") }
        if let water = ctx.waterC, water < 12 {
            adjustments.append("저수온입니다. 바닥에서 30cm만 공략하고, 밑밥은 조금만 자주 줍니다.")
        }
        return TacklePlan(
            id: "감성돔",
            species: "감성돔",
            method: "구멍찌 반유동",
            summary: "저조가 끝나 물이 들기 시작할 때, 바닥 바로 위를 크릴로 공략합니다.",
            why: "감성돔은 조류가 살아나는 들물 초반과 만조 직전을 좋아합니다. 채비는 바닥을 읽되 걸리지 않게 30cm 위를 유지하는 것이 핵심입니다.",
            rod: "1.5~5.3m 감성돔 전용대, 또는 1호~530 찌낚시 릴대",
            reel: "2500~4000번 스피닝. 드랙은 손이 살짝 아플 정도로만.",
            mainLine: "나일론 원줄 2.5~3호. 바람 불면 2.5호를 유지하고 찌를 키웁니다.",
            leader: leader,
            terminal: "\(floatText) 감성돔 바늘 4호, 크릴 2마리(꼬리 자름).",
            bait: "주 미끼는 크릴. 예비로 홍갯지렁이 또는 청갯지렁이.",
            chum: "크릴 3장, 빵가루 2컵, 파우더 1컵. 바닷물에 개어 주먹으로 쥐면 천천히 풀릴 정도.",
            rig: "반유동. 찌매듭은 수심+1m에 두고, 좁쌀봉돌 2~3개로 목줄이 자연스럽게 서게.",
            depth: "공략 수심은 바닥 확인 후 30~50cm 위. 조류가 세면 목줄을 50cm 줄입니다.",
            bite: "찌가 한 뼘 이상 천천히 잠기거나 끌려가면 바로 챔. 잔 찍힘에는 챔질하지 않습니다.",
            steps: [
                "도착해서 10분은 밑밥만 줍니다. 한 주걱씩, 조류가 흐르는 쪽으로.",
                "전유동으로 바닥 수심을 재고, 그 수심에서 30cm를 뺀 위치에 찌매듭을 고정합니다.",
                "크릴 2마리의 꼬리를 잘라 바늘을 머리에서 넣습니다.",
                "첫 투척은 조류 상류 45도. 찌가 포인트에 도착할 때 밑밥을 한 주걱 더 맞춥니다.",
                "10분간 입질이 없으면 수심을 20cm 내리고, 그래도 없으면 자리를 5m만 옮깁니다.",
                "만조 1시간 전부터는 밑밥을 줄이고 채비 정확도만 유지합니다.",
            ],
            bag: seaBag(night: ctx.night) + ["크릴 아이스박스, 밑밥통, 찌와 수중찌 한 호수 위·아래"],
            avoid: [
                "만조에 바닥을 질질 끄는 채비. 밑걸림만 납니다.",
                "입질이 없는데 밑밥을 퍼붓는 것. 고기가 떠오르거나 포인트를 버립니다.",
                "목줄 3호 이상. 감성돔은 목줄이 굵으면 입질이 끊깁니다.",
            ],
            adjustments: adjustments
        )
    }

    private static func benge(_ ctx: FieldContext) -> TacklePlan {
        let leader = ctx.stained ? "카본 1.5호, 2m" : "카본 0.8~1.2호, 2.5~3.5m"
        var adjustments: [String] = []
        if windHeavy(ctx) { adjustments.append("제로찌 대신 00~G2 구멍찌로 바꾸고, 뒷줄을 더 눕히지 않습니다.") }
        if (ctx.waterC ?? 20) >= 22 { adjustments.append("수온이 높습니다. 밑밥을 잘게, 적게, 자주. 목줄은 한 단계 내립니다.") }
        return TacklePlan(
            id: "벵에돔",
            species: "벵에돔",
            method: "제로찌 전유동",
            summary: "밑밥에 뜬 벵에돔을 가벼운 찌와 긴 목줄로 자연스럽게 흘립니다.",
            why: "벵에돔은 경계가 셉니다. 채비가 무겁거나 목줄이 굵으면 미끼만 보고 돌아섭니다. 조류가 약한 들물에 유리합니다.",
            rod: "1호~530 또는 0.8호 전유동 전용대",
            reel: "2500번. 라인 트러블이 없는 얕은 스풀.",
            mainLine: "나일론 1.5~2호",
            leader: leader,
            terminal: windHeavy(ctx) ? "구멍찌 00~G2, 벵에돔 바늘 4~5호" : "제로찌 또는 00 구멍찌, 벵에돔 바늘 4~5호",
            bait: "크릴 1~2마리. 활크릴이면 꼬리를 조금만 자릅니다.",
            chum: "크릴을 잘게 다지고 빵가루로 점도를 맞춥니다. 한 번에 많이 주지 않습니다.",
            rig: "전유동. 수중찌는 찌보다 한 단계 무겁게, 원줄에 좁쌀은 거의 달지 않습니다.",
            depth: "먼저 3~5m를 흘려 보고, 입질이 없으면 2m씩 내립니다. 바닥은 마지막 수단입니다.",
            bite: "원줄이 멈추거나 살짝 풀려 나가면 한 박자 뒤 챔. 강한 챔질은 목줄이 터집니다.",
            steps: [
                "자리 잡자마자 밑밥을 콩알만큼 계속 뿌려 먹이띠를 만듭니다.",
                "제로찌가 잠기지 않게 뒷줄을 살짝 견제하며 흘립니다.",
                "같은 라인을 5번 반복한 뒤에야 수심을 바꿉니다.",
                "바늘에 크릴 내장이 터지면 바로 새 미끼로 바꿉니다.",
                "고기가 보이는데 안 먹으면 목줄을 0.6~0.8호로 내립니다.",
            ],
            bag: seaBag(night: ctx.night) + ["제로찌, 00찌, 목줄 0.8·1.2·1.5호"],
            avoid: ["무거운 수중찌로 억지 잠수", "밑밥 한 바가지", "바닥 걸림이 반복되는데 같은 수심 유지"],
            adjustments: adjustments
        )
    }

    private static func nungeo(_ ctx: FieldContext) -> TacklePlan {
        let lure = ctx.stained
            ? "차트·골드 미노우 12~15cm, 또는 바이브 28~40g. 탁한 물에서는 실루엣이 큰 것."
            : "내추럴 미노우 11~14cm, 새벽에는 은색, 밤에는 검은등."
        var adjustments: [String] = []
        if windHeavy(ctx) { adjustments.append("비거리 때문에 미노우보다 메탈 지그·바이브를 먼저 씁니다.") }
        if ctx.night { adjustments.append("야간에는 느리게, 바닥에서 한 뼘만 띄워 트위치합니다.") }
        return TacklePlan(
            id: "농어",
            species: "농어",
            method: "미노우·바이브",
            summary: "들물이 구조물에 부딪히는 가장자리를 루어로 끊어서 공략합니다.",
            why: "농어는 새벽에 구조물 그림자와 조경(물이 부딪히는 경계)에 붙습니다. 채비를 많이 던지기보다 같은 라인을 각도를 바꿔 반복하는 편이 낫습니다.",
            rod: "쇼어 88~96ML 또는 M, 루어 10~35g 대응",
            reel: "3000~4000번",
            mainLine: "PE 0.8~1호",
            leader: "카본 리더 16~20lb, 1~1.2m",
            terminal: lure,
            bait: "루어가 주력. 살아있는 전갱이가 있으면 그것은 예비입니다.",
            chum: "밑밥 없음. 소음과 착수 횟수를 줄입니다.",
            rig: "리더 직결 또는 FG 매듭. 도래는 달지 않습니다.",
            depth: "표층~중층. 방파제 발밑, 테트라포드 모서리, 수문 앞 조경.",
            bite: "탁 치는 입질에 바로 드랙을 확인하고 헤드를 물 밖으로 빼지 않게 버팁니다.",
            steps: [
                "헤드랜턴은 물 쪽을 비추지 않습니다.",
                "첫 10분은 발밑 3m만 짧게 검색합니다.",
                "미노우는 2초 잠행 후 트위치 2번, 1초 쉼. 이 리듬을 고정합니다.",
                "같은 자리를 15분 공략하고, 없으면 30m만 이동합니다.",
                "광량이 올라가면 미노우를 작고 자연색으로 바꿉니다.",
            ],
            bag: seaBag(night: true) + ["플라이어, 립그립, 여분 트레블 훅"],
            avoid: ["한 포인트를 한 번만 던지고 걷기", "원줄만 잡고 맨손으로 입 근처 가기", "파도가 방파제를 넘는 날의 고집"],
            adjustments: adjustments
        )
    }

    private static func gwang(_ ctx: FieldContext) -> TacklePlan {
        var sinker = "다운샷 봉돌 7~14g"
        if windHeavy(ctx) || tideStrong(ctx) { sinker = "다운샷 봉돌 14~21g. 채비가 뜨면 무겁게." }
        var adjustments: [String] = []
        if ctx.stained { adjustments.append("물색이 탁하면 차트 웜, 맑으면 내추럴 새우색.") }
        return TacklePlan(
            id: "광어",
            species: "광어",
            method: "다운샷",
            summary: "모래와 뻘이 만나는 바닥을 웜이 살짝 끌리게 기다립니다.",
            why: "광어는 바닥의 먹이를 기다립니다. 채비를 많이 움직이지 말고, 바닥을 확인한 뒤 아주 작게 튀기는 동작이 맞습니다.",
            rod: "쇼어 90M~MH, 또는 광어 다운샷 전용대",
            reel: "3000~4000번",
            mainLine: "PE 0.8~1.2호",
            leader: "카본 12~16lb, 1m",
            terminal: "\(sinker), 훅 2~3호, 새우 웜 3~4인치",
            bait: "웜이 기본. 청갯지렁이 원투는 백사장 예비 채비입니다.",
            chum: "없음",
            rig: "다운샷. 바늘은 봉돌 위 20~30cm. 웜은 꼬리가 자유롭게.",
            depth: "바닥. 걸리면 10m만 옆으로 이동합니다. 암초 한가운데는 피합니다.",
            bite: "무게가 사라지거나 툭 치면 릴을 한 바퀴 감은 뒤 챔.",
            steps: [
                "착수 후 여유 원줄을 주고 바닥이 닿을 때까지 셉니다.",
                "로드를 45도로 두고 10초에 한 번, 로드팁만 짧게 튀깁니다.",
                "5분마다 10m씩 부채꼴로 옮깁니다.",
                "입질이 없던 라인을 조류가 바뀌면 다시 한 번만 반복합니다.",
            ],
            bag: seaBag(night: ctx.night) + ["웜 케이스, 봉돌 7·14·21g", "백사장용 원투 채비(원줄 4호, 봉돌 30~40호) 예비"],
            avoid: ["빠른 릴링", "암초 틈에 웜을 처박기", "바늘이 웜 등 밖으로 크게 나온 상태"],
            adjustments: adjustments
        )
    }

    private static func ureok(_ ctx: FieldContext) -> TacklePlan {
        let weight = tideStrong(ctx) ? "지그헤드 20~30g" : "지그헤드 10~20g"
        return TacklePlan(
            id: "우럭",
            species: "우럭",
            method: "지그헤드 웜",
            summary: "방파제 발밑과 침선 가장자리를 바닥 튀김으로 끊습니다.",
            why: "우럭은 은신처 바로 앞에 있습니다. 멀리 던지기보다 구조물 경계의 바닥을 짧게 튀기는 것이 맞습니다.",
            rod: "락피시 86~90ML~M",
            reel: "2500~3000번",
            mainLine: "PE 0.6~0.8호",
            leader: "카본 10~14lb, 80cm",
            terminal: "\(weight), 그럽 2~3인치. 기본색은 차로, 맑으면 펄.",
            bait: "웜. 예비로 청갯지렁이 밑걸림 채비.",
            chum: "없음. 밑밥은 잔챙이만 모읍니다.",
            rig: "지그헤드 직결. 밑걸림이 심하면 다운샷으로 바꿉니다.",
            depth: "바닥에서 30cm를 튀긴 뒤 3초 정지.",
            bite: "무게가 훅 빠지면 즉시 챔. 우럭은 이물감을 빨리 느낍니다.",
            steps: [
                "테트라포드 모서리와 계단 아래를 먼저 3캐스팅.",
                "바닥 접촉 후 로드를 살짝 들었다고 바로 감습니다. 점프는 작게.",
                "밑걸림 2번이면 그 라인은 버리고 각도를 바꿉니다.",
                "조류가 멈춘 한 시간은 채비 무게를 한 단계 내립니다.",
            ],
            bag: seaBag(night: ctx.night) + ["지그헤드 7·14·20g", "그럽 차로·펄·핑크"],
            avoid: ["무거운 채비로 구조물 안쪽 억지 탐색", "드랙을 잠가 놓고 힘으로 뽑기"],
            adjustments: tideStrong(ctx) ? ["조류가 세서 지그헤드를 무겁게 잡았습니다."] : []
        )
    }

    private static func bollak(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "볼락",
            species: "볼락",
            method: "야간 라이트 지그헤드",
            summary: "해가 진 뒤 방파제 불빛 가장자리의 중층을 작게 흔듭니다.",
            why: "볼락은 밤과 저수온에 무리가 붙습니다. 채비는 가볍고, 액션은 작아야 합니다. 낮에는 기대하지 않습니다.",
            rod: "아징 76~82UL~L",
            reel: "2000번",
            mainLine: "PE 0.3~0.4호",
            leader: "에스테르 또는 카본 2~3lb, 1m",
            terminal: "지그헤드 1~2.5g, 아지 웜 1.5~2인치",
            bait: "웜. 색은 글로우, 펄, 핑크 순으로 바꿉니다.",
            chum: "크릴을 잘게 조금. 많이 주면 잔고기만 올라옵니다.",
            rig: "지그헤드. 바늘 끝이 웜 등에서 살짝만 나오게.",
            depth: "2~6m. 바닥을 확인한 뒤 1m 위부터 한 바퀴씩 올립니다.",
            bite: "톡 또는 무게 소멸. 강한 챔질은 입을 찢거나 바늘이 빠집니다.",
            steps: [
                "일몰 30분 전부터 자리를 잡고 불빛 경계를 표시해 둡니다.",
                "1.5g으로 카운트 5, 10, 15를 각각 5번씩.",
                "입질 수심이 나오면 그 카운트만 30분 반복합니다.",
                "무리가 흩어지면 10m 이동 후 같은 카운트.",
            ],
            bag: seaBag(night: true) + ["지그헤드 1·1.5·2.5g", "글로우 웜"],
            avoid: ["낮에 같은 채비로 시간 쓰기", "3g 이상 지그헤드로 시작", "랜턴을 수면에 직접 비추기"],
            adjustments: ctx.night ? [] : ["아직 낮입니다. 볼락 채비는 해가 진 뒤에 묶으세요."]
        )
    }

    private static func eging(_ ctx: FieldContext) -> TacklePlan {
        let size = (ctx.waterC ?? 18) >= 20 ? "에기 3.0~3.5호" : "에기 2.5~3.0호"
        var adjustments: [String] = []
        if windHeavy(ctx) { adjustments.append("역풍이면 팁런용 딥 에기나 한 호수 큰 에기로 비거리를 맞춥니다.") }
        if ctx.stained { adjustments.append("물색이 탁하면 골드·오렌지 베이스, 맑으면 내추럴 베이스.") }
        return TacklePlan(
            id: "무늬오징어",
            species: "무늬오징어",
            method: "에깅",
            summary: "바닥을 한 번 찍고, 샤크리 두 번, 폴로 자연 낙하시키는 리듬을 고정합니다.",
            why: "무늬오징어는 낙하하는 에기를 쫓습니다. 액션 횟수보다 폴(떨어지는 시간)이 입질 구간입니다.",
            rod: "에깅 83~86ML",
            reel: "3000번",
            mainLine: "PE 0.6~0.8호",
            leader: "카본 8~12lb, 1~1.5m. 밑걸림 구간이면 짧게.",
            terminal: "\(size). 기본은 골드 베이스 내추럴, 밤에는 글로우.",
            bait: "에기만. 미끼를 달지 않습니다.",
            chum: "없음",
            rig: "리더 직결. 스냅 도래는 작은 것만.",
            depth: "바닥 접촉 후 1~2m 폴. 여밭과 암초 경계.",
            bite: "폴 중 원줄이 멈추거나 탁 치면 그대로 감아 올립니다. 바로 강한 챔은 훅이 빠집니다.",
            steps: [
                "에기를 45도로 캐스팅하고 바닥이 닿을 때까지 셉니다.",
                "로드를 살짝 들어 샤크리 2번, 원줄에 텐션을 유지한 채 폴.",
                "한 라인에 이 리듬 5회. 없으면 10m 이동.",
                "새벽과 해 질 녘에는 같은 라인을 얕은 쪽부터 다시 검색합니다.",
                "걸린 뒤에는 드랙을 풀고 펌핑. 물 밖에서 잉크를 피하려면 뜰채를 씁니다.",
            ],
            bag: seaBag(night: ctx.night) + ["에기 2.5·3.0·3.5호 기본색과 차트", "뜰채"],
            avoid: ["바닥을 질질 끌기", "폴 없이 계속 샤크리", "맨손으로 다리 잡기"],
            adjustments: adjustments
        )
    }

    private static func gap(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "갑오징어",
            species: "갑오징어",
            method: "에깅(팁런 리듬의 얕은 공략)",
            summary: "항 입구와 모래 가장자리를 작고 느린 에기로 낮~해 질 녘에 검색합니다.",
            why: "갑오징어는 무늬오징어보다 얕고 느립니다. 폴을 길게, 샤크리는 작게.",
            rod: "에깅 83ML",
            reel: "2500~3000번",
            mainLine: "PE 0.6호",
            leader: "카본 8lb, 1m",
            terminal: "에기 2.5호. 내추럴·금색. 야광은 해 진 뒤만.",
            bait: "에기",
            chum: "없음",
            rig: "직결",
            depth: "2~8m 모래와 잘피, 항 입구 물골",
            bite: "묵직하게 멈추면 기다렸다가 천천히 감습니다.",
            steps: [
                "무늬오징어보다 샤크리를 절반만 합니다.",
                "바닥 접촉 후 3초 이상 폴.",
                "항 입구 양쪽 물골을 교차로 10캐스팅.",
                "걸리면 빨판이 떨어지기 전에 뜰채로 받습니다.",
            ],
            bag: seaBag(night: ctx.night) + ["에기 2.5호", "뜰채"],
            avoid: ["빠른 저킹", "깊은 암초만 고집"],
            adjustments: ctx.stained ? ["탁한 날에는 금색 베이스로 바꿉니다."] : []
        )
    }

    private static func jukkumi(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "주꾸미",
            species: "주꾸미",
            method: "애자·채비 원투",
            summary: "방파제 바깥 모래와 뻘 바닥을 짧은 호핑으로 확인합니다.",
            why: "주꾸미는 바닥의 소라·돌 틈에 있습니다. 채비를 멀리 던진 뒤 바닥을 짧게 끊어 주는 동작이면 충분합니다.",
            rod: "주꾸미대 또는 라이트 에깅대 80~86",
            reel: "2500번",
            mainLine: "PE 0.6호",
            leader: "카본 6~8lb, 50cm",
            terminal: "애자 8~15g, 또는 주꾸미 채비(봉돌+훅 2~3개). 미끼는 새우·오징어 조각.",
            bait: "냉동 새우, 오징어 다리. 미끼가 떨어지면 바로 갈아 줍니다.",
            chum: "없음",
            rig: "애자 직결 또는 채비 도래.",
            depth: "바닥. 3초 정지 후 한 발짝 호핑.",
            bite: "묵직한 무게. 바로 뽑지 말고 두 박자 기다린 뒤 감습니다.",
            steps: [
                "바깥 모래밭을 부채꼴로 나눕니다.",
                "착저 후 로드팁으로 작게 두 번, 3초 쉼.",
                "한 방향 10번, 없으면 옆 방향.",
                "사이즈가 작으면 그 자리는 놓고 50m 이동합니다.",
            ],
            bag: seaBag(night: false) + ["애자 8·12·15g", "새우 미끼", "뜰채"],
            avoid: ["큰 에기로 대체", "암초 한가운데 채비 버리기"],
            adjustments: windHeavy(ctx) ? ["바람이 있어 애자 15g을 기본으로 했습니다."] : []
        )
    }

    private static func jeongang(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "전갱이",
            species: "전갱이",
            method: "사비키",
            summary: "방파제 중층에 무리가 붙는 새벽·해 질 녘을 짧은 사비키로 받습니다.",
            why: "전갱이는 무리 낚시입니다. 채비를 가볍게 하고, 걸린 뒤에도 같은 수심을 유지하는 것이 조과를 가릅니다.",
            rod: "1호 원투 또는 사비키대",
            reel: "2500번",
            mainLine: "나일론 2호",
            leader: "목줄 1~1.5호, 가지 3개, 간격 25cm",
            terminal: "사비키 7~8호 바늘, 어피 또는 크리스탈. 봉돌 5~10호.",
            bait: "바늘에 이미 어피가 있으면 추가 미끼는 크릴 한 꼬리만.",
            chum: "크릴을 조금 으깨 수면에. 많이 주면 찌올림만 나빠집니다.",
            rig: "가지채비 3본. 맨 아래 봉돌.",
            depth: "2~5m. 입질 층이 나오면 봉돌을 한 호수만 조절.",
            bite: "계속 톡톡하면 한 마리만 더 노리고 바로 올립니다. 세 마리를 기다리다 떨어집니다.",
            steps: [
                "해 뜨기 전 또는 해 지기 30분에 자리를 잡습니다.",
                "봉돌이 바닥에 닿기 전 카운트에서 멈춥니다.",
                "입질 층을 메모하고 그 카운트만 반복합니다.",
                "무리가 빠지면 랜턴을 끄고 5분 쉽니다.",
            ],
            bag: seaBag(night: true) + ["사비키 예비 2세트", "봉돌 5·8·10호"],
            avoid: ["너무 큰 봉돌로 바닥만 두드리기", "세 마리를 무조건 기다리기"],
            adjustments: []
        )
    }

    private static func sung(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "숭어",
            species: "숭어",
            method: "찌낚시",
            summary: "들물에 포구로 들어오는 표층~중층을 길고 가는 목줄로 흘립니다.",
            why: "숭어는 시야가 좋습니다. 목줄이 굵거나 찌가 크면 접근하지 않습니다.",
            rod: "1~530 민장대 또는 릴찌 1호",
            reel: "2500번. 민장이면 릴 없음.",
            mainLine: "나일론 1.5호",
            leader: "0.8~1호, 1.5m",
            terminal: "구멍찌 5B~1호, 숭어 바늘 4~5호",
            bait: "크릴 또는 식물성 미끼(빵·떡밥 소량). 현장 물색에 맞춰 하나만.",
            chum: "빵가루와 크릴 가루를 조금씩.",
            rig: "반유동 또는 전유동. 수면 아래 50cm~2m.",
            depth: "표층부터 1m씩.",
            bite: "찌가 스르륵 끌리면 타이밍을 한 박자 늦춰 챔.",
            steps: [
                "고기가 튀는 방향을 1분 관찰하고 그 앞에 밑밥을 뿌립니다.",
                "채비는 관찰한 라인의 상류에 넣습니다.",
                "입질이 예민하면 목줄을 0.6호까지 내립니다.",
            ],
            bag: seaBag(night: false) + ["찌 5B·1호", "목줄 0.8·1호"],
            avoid: ["무거운 구멍찌", "바닥 채비로 시간 보내기"],
            adjustments: windHeavy(ctx) ? ["바람이 있어 찌를 1호로 올렸습니다. 목줄은 그대로 가늘게 유지하세요."] : []
        )
    }

    private static func bung(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "붕장어",
            species: "붕장어",
            method: "야간 원투",
            summary: "여름~초가을 밤, 방파제 바깥 모래바닥에 고등어 조각을 두고 기다립니다.",
            why: "붕장어는 밤에 냄새로 접근합니다. 자주 던지지 말고, 미끼가 바닥에서 냄새를 내게 둡니다.",
            rod: "원투 15~25호 또는 4.2m 이상 원투대",
            reel: "원투 4000번 이상, 드랙 여유",
            mainLine: "나일론 5~6호",
            leader: "목줄 4호, 50cm. 쓸림이 있으면 목줄을 짧게.",
            terminal: "붕장어 바늘 12~14호, 봉돌 25~35호, 고등어·꽁치 조각",
            bait: "신선한 고등어 등살. 피가 남은 조각이 낫습니다.",
            chum: "없음",
            rig: "외줄 또는 2본. 바닥 고정.",
            depth: "바닥. 방파제에서 바깥 모래.",
            bite: "원줄이 천천히 풀리면 3초 기다렸다가 강하게 챔.",
            steps: [
                "해가 진 뒤 자리를 잡고 2대까지 각도를 벌려 던집니다.",
                "20분마다 미끼 상태만 확인하고, 멀쩡하면 다시 같은 자리에.",
                "입질 후 억지로 들어 올리지 말고 드랙으로 받아 냅니다.",
                "바늘 제거는 플라이어. 맨손 금지.",
            ],
            bag: seaBag(night: true) + ["봉돌 25·35호", "고등어", "헤드랜턴"],
            avoid: ["낮에 같은 채비 고집", "미끼를 5분마다 교체", "방파제를 넘는 파도"],
            adjustments: []
        )
    }

    private static func bungeo(_ ctx: FieldContext) -> TacklePlan {
        let bait = (ctx.waterC ?? 18) < 15 ? "지렁이 또는 글루텐. 저수온에는 동물성." : "글루텐 또는 옥수수. 수온이 오르면 곡물."
        return TacklePlan(
            id: "붕어",
            species: "붕어",
            method: "바닥·내림",
            summary: "수초 가장자리의 바닥을 조용히 두고, 새벽과 해 질 녘만 집중합니다.",
            why: "붕어는 소음과 채비 그림자에 민감합니다. 자리를 자주 옮기지 않고, 같은 지점에 미끼가 머물게 하는 것이 먼저입니다.",
            rod: "바닥 3.6~4.0칸, 또는 민물 릴대",
            reel: "민물 스피닝 2000~2500. 대물 바닥이면 원줄 여유.",
            mainLine: "원줄 2~3호",
            leader: "목줄 1.5~2호, 30~40cm",
            terminal: "붕어 바늘 7~8호, 봉돌은 바닥에서 움직이지 않을 만큼만",
            bait: bait,
            chum: "집어제 한 주걱. 자리를 잡기 전에 한 번, 이후에는 아주 적게.",
            rig: "외바늘 또는 두 바늘. 바닥 고정. 수초 구멍이면 짧게.",
            depth: "바닥. 수초 경계에서 안쪽으로 한 발.",
            bite: "찌가 올라오거나 천천히 잠기면 끝까지 보고 챔. 첫 움직임에 채지 않습니다.",
            steps: [
                "의자 소음을 줄이고 10분 자리를 안정시킵니다.",
                "수초 구멍을 두 곳만 정하고 번갈아 둡니다.",
                "30분 입질이 없으면 미끼 종류만 바꾸고 자리는 유지합니다.",
                "새벽 1시간과 해 지기 1시간을 핵심으로 잡고 한낮은 쉽니다.",
            ],
            bag: freshBag(night: ctx.night) + ["글루텐, 옥수수, 지렁이", "여분 찌와 봉돌"],
            avoid: ["자리를 10분마다 옮기기", "집어제를 계속 퍼붓기", "굵은 목줄 3호"],
            adjustments: ctx.stained ? ["비 뒤 흙탕이면 미끼를 지렁이로 바꾸고 냄새를 세게 합니다."] : []
        )
    }

    private static func bass(_ ctx: FieldContext) -> TacklePlan {
        let lure = ctx.stained
            ? "차트 스피너베이트 3/8oz 또는 블랙 블루 웜"
            : "그린펌킨 웜 4~5인치, 프리리그. 아침에는 미노우."
        return TacklePlan(
            id: "배스",
            species: "배스",
            method: "소프트베이트",
            summary: "수온이 맞는 아침·저녁에 스트럭처(수초, 그늘, 급심) 경계만 노립니다.",
            why: "배스는 은신처에서 나와 먹이를 덮칩니다. 넓은 구간을 걷기보다 경계 3m를 여러 각도로 던지는 편이 낫습니다.",
            rod: "배스 66~70M, 또는 ML",
            reel: "베이트 또는 2500~3000 스피닝",
            mainLine: "합사 1~1.5호 또는 나일론 12lb",
            leader: "프리리그면 카본 10~14lb, 50cm. 스피너베이트는 직결.",
            terminal: lure,
            bait: "루어",
            chum: "없음",
            rig: "프리리그 또는 텍사스. 바닥 걸림이 심하면 텍사스.",
            depth: "수초 가장자리, 그늘선, 급심 꼭대기.",
            bite: "무게가 탁 실리면 훅셋. 웜은 한 박자 늦춰도 됩니다.",
            steps: [
                "해 뜰 때 얕은 곳, 해가 올라가면 그늘과 깊은 경계로 옮깁니다.",
                "한 스트럭처에 5캐스팅. 각도를 바꿉니다.",
                "입질이 약하면 웜을 한 사이즈 줄입니다.",
                "한낮은 그늘만 하고, 해 지기 한 시간 전에 다시 얕은 곳으로.",
            ],
            bag: freshBag(night: ctx.night) + ["웜, 프리 훅, 불릿 싱커 3~7g", "플라이어"],
            avoid: ["같은 색만 하루 종일", "보트 없이 위험한 급경사 접근"],
            adjustments: []
        )
    }

    private static func sogari(_ ctx: FieldContext) -> TacklePlan {
        return TacklePlan(
            id: "쏘가리",
            species: "쏘가리",
            method: "미노우",
            summary: "여울 가장자리와 바위 뒤를 작고 빠른 미노우로 다운크로스합니다.",
            why: "쏘가리는 흐름이 느려지는 바위 뒤에 있습니다. 루어는 흐름을 가로질러 그 느린 물로 떨어뜨립니다.",
            rod: "트래웃 또는 쏘가리 60~66L~ML",
            reel: "2000~2500번",
            mainLine: "PE 0.6호",
            leader: "카본 8~12lb, 1m",
            terminal: "싱킹 미노우 7~9cm, 내추럴 은색. 여울이 세면 헤비 싱킹.",
            bait: "루어. 살아있는 피라미는 현장 규정이 허용할 때만.",
            chum: "없음",
            rig: "직결. 스냅은 작은 것.",
            depth: "여울목 아래 30cm~1m, 바위 뒤 와류.",
            bite: "짧은 컨택에 즉시 훅셋. 드랙은 약간 풀어 둡니다.",
            steps: [
                "상류에서 하류를 보며 사람의 그림자가 물에 안 가게 섭니다.",
                "바위 뒤로 미노우가 떨어지게 다운크로스.",
                "한 바위에 3회. 없으면 다음 바위.",
                "오전이 지나 수온이 오르면 그늘진 깊은 와류만 남깁니다.",
            ],
            bag: freshBag(night: false) + ["미노우 3개", "립그립", "미끄럼 방지 신발"],
            avoid: ["여울 한가운데로 들어가기", "큰 크랭크베이트로 시작", "산란기 무리한 포획. 지역 규정을 먼저 확인"],
            adjustments: []
        )
    }
}
