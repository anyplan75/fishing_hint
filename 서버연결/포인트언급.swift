import Foundation

// 기준점 일대의 공개 글과 공개 포인트를 인공지능이 읽게 합니다.
// 좌표는 인공지능이 적지 않습니다. 목록에 있는 자리이거나, 글에 적힌 지명을 지도에서 확인한 자리만 남깁니다.

enum MentionFinder {
    struct KnownPoint {
        var point: FishingPoint
        var distanceKm: Double
    }

    struct Outcome {
        var points: [FishingPoint]
        var intro: String
        var failure: String?
    }

    static func find(
        anchorName: String,
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        notes: [PublicFishingNote],
        known: [KnownPoint],
        mapboxToken: String,
        geminiKey: String
    ) async -> Outcome {
        let localNotes = Array(notes.prefix(24))
        let localKnown = Array(known.prefix(20))
        let posts = localNotes.filter { $0.sourceName != "유튜브" }
        let videos = localNotes.filter { $0.sourceName == "유튜브" }
        let area = anchorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = area.isEmpty ? "기준점" : area
        if posts.isEmpty && videos.isEmpty && localKnown.isEmpty {
            return Outcome(
                points: [],
                intro: "",
                failure: "이 근처에서 읽을 공개 글이 없습니다."
            )
        }
        let key = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return Outcome(
                points: [],
                intro: "",
                failure: "인공지능 없음. 비밀 파일에 GEMINI_API_KEY 가 없습니다. 위치를 지어 넣지 않았습니다."
            )
        }
        let corpus = corpusText(notes: localNotes, known: localKnown)
        let script = prompt(anchorName: title, radiusKm: radiusKm, posts: posts, videos: videos, known: localKnown)
        let drafts: [MentionDraft]
        do {
            drafts = try await BriefingClient.readMentions(script: script, apiKey: key)
        } catch {
            return Outcome(
                points: [],
                intro: "",
                failure: "인공지능이 공개 자료를 읽지 못했습니다. 위치를 지어 넣지 않았습니다."
            )
        }
        guard !drafts.isEmpty else {
            return Outcome(
                points: [],
                intro: "",
                failure: "이 일대 자료에서 괜찮은 포인트를 고르지 못했습니다. 위치를 못 정한 글은 넣지 않았습니다."
            )
        }
        var resolved: [FishingPoint] = []
        var missed = 0
        for draft in drafts {
            if let point = await resolve(
                draft,
                corpus: corpus,
                notes: localNotes,
                videos: videos,
                known: localKnown,
                latitude: latitude,
                longitude: longitude,
                radiusKm: radiusKm,
                mapboxToken: mapboxToken
            ) {
                appendUnique(point, to: &resolved)
            } else {
                missed += 1
            }
            if resolved.count >= 10 { break }
        }
        if resolved.isEmpty {
            return Outcome(
                points: [],
                intro: "",
                failure: "언급된 자리의 위치를 기준점 반경 안에서 확인하지 못했습니다. 못 정한 글은 넣지 않았습니다."
            )
        }
        var intro = "\(title) 일대의 공개 글 \(posts.count)건, 유튜브 공개 영상 \(videos.count)건, 공개 포인트 \(localKnown.count)곳을 읽고, 위치를 정한 \(resolved.count)곳만 받은 날씨·물때로 봤습니다."
        if missed > 0 {
            intro += " 위치를 못 정한 \(missed)건은 빼 두었습니다."
        }
        return Outcome(points: resolved, intro: intro, failure: nil)
    }

    private static func prompt(
        anchorName: String,
        radiusKm: Double,
        posts: [PublicFishingNote],
        videos: [PublicFishingNote],
        known: [KnownPoint]
    ) -> String {
        var lines = [
            "기준점: \(anchorName)",
            "반경: \(Int(radiusKm))km",
            "공개 글:",
        ]
        if posts.isEmpty {
            lines.append("- 없음")
        }
        for note in posts {
            let place = note.placeLabel.isEmpty ? "지역 없음" : note.placeLabel
            let summary = String(note.summary.prefix(160))
            lines.append("- \(place) | \(summary)")
        }
        lines.append("유튜브 공개 영상:")
        if videos.isEmpty {
            lines.append("- 없음")
        }
        for note in videos {
            lines.append("- \(String(note.summary.prefix(160)))")
        }
        lines.append("공개 포인트:")
        if known.isEmpty {
            lines.append("- 없음")
        }
        for (index, item) in known.enumerated() {
            let km = String(format: "%.1f", item.distanceKm)
            lines.append("- P\(index) \(item.point.name) \(item.point.place.title) 기준점에서 \(km)km")
        }
        return lines.joined(separator: "\n")
    }

    private static func corpusText(notes: [PublicFishingNote], known: [KnownPoint]) -> String {
        let noteText = notes.map { "\($0.placeLabel) \($0.summary)" }.joined(separator: "\n")
        let pointText = known.map { $0.point.name }.joined(separator: "\n")
        return noteText + "\n" + pointText
    }

    private static func resolve(
        _ draft: MentionDraft,
        corpus: String,
        notes: [PublicFishingNote],
        videos: [PublicFishingNote],
        known: [KnownPoint],
        latitude: Double,
        longitude: Double,
        radiusKm: Double,
        mapboxToken: String
    ) async -> FishingPoint? {
        let basis = quotedBasis(draft.basis, corpus: corpus)
        if draft.isPoint {
            guard let item = knownPoint(draft.value, known: known) else { return nil }
            guard item.distanceKm <= radiusKm + 0.4 else { return nil }
            var point = item.point
            point.source = "공개포인트"
            if !basis.isEmpty { point.memo = basis }
            point.targetMemo = mergeSpecies(point.targetMemo, tiedText(place: point.name, basis: basis, notes: notes))
            return point
        }
        let place = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard placeAppears(place, in: corpus) else { return nil }
        let looked = await PlaceNameClient.forward(query: place, latitude: latitude, longitude: longitude, token: mapboxToken)
        guard looked.reach == .ok else { return nil }
        let near = looked.hits
            .map { hit -> (PlaceNameClient.Hit, Double) in
                (hit, Geo.kilometers(latitude, longitude, hit.latitude, hit.longitude))
            }
            .filter { $0.1 <= radiusKm + 1 }
            .min { $0.1 < $1.1 }
        guard let chosen = near else { return nil }
        let name = placeAppears(draft.name, in: corpus) ? draft.name : place
        let fromVideo = videos.contains { $0.summary.contains(place) }
        return FishingPoint(
            id: "mention-\(stableID(place, chosen.0.latitude, chosen.0.longitude))",
            name: name,
            latitude: chosen.0.latitude,
            longitude: chosen.0.longitude,
            place: .custom,
            water: .unknown,
            source: fromVideo ? "유튜브" : "공개글",
            bottom: "",
            targetMemo: TackleBook.names(in: tiedText(place: name, basis: basis, notes: notes)).joined(separator: ", "),
            measuredTempC: nil,
            memo: basis.isEmpty ? "공개 글에 나온 \(place)" : basis
        )
    }

    private static func tiedText(place: String, basis: String, notes: [PublicFishingNote]) -> String {
        let name = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let tied = notes.filter { note in
            guard name.count >= 2 else { return false }
            return note.summary.contains(name) || note.placeLabel.contains(name)
        }
        return ([basis] + tied.map(\.summary)).joined(separator: "\n")
    }

    private static func mergeSpecies(_ current: String, _ text: String) -> String {
        var names = TackleBook.names(in: current)
        for name in TackleBook.names(in: text) where !names.contains(name) {
            names.append(name)
        }
        return names.joined(separator: ", ")
    }

    private static func knownPoint(_ raw: String, known: [KnownPoint]) -> KnownPoint? {
        let token = raw.replacingOccurrences(of: " ", with: "").uppercased()
        if token.hasPrefix("P"), let index = Int(token.dropFirst()), known.indices.contains(index) {
            return known[index]
        }
        return known.first { $0.point.name == raw.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static let blockedPlaces: Set<String> = ["", "-", "없음", "미정", "전국", "기타", "기타지역", "지역없음", "지역 없음"]

    private static func placeAppears(_ name: String, in corpus: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !blockedPlaces.contains(trimmed) else { return false }
        return corpus.contains(trimmed)
    }

    private static func quotedBasis(_ basis: String, corpus: String) -> String {
        let trimmed = basis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, corpus.contains(trimmed) else { return "" }
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }

    private static func appendUnique(_ point: FishingPoint, to points: inout [FishingPoint]) {
        let duplicate = points.contains { existing in
            existing.name == point.name
                || Geo.kilometers(existing.latitude, existing.longitude, point.latitude, point.longitude) < 0.4
        }
        if !duplicate { points.append(point) }
    }

    private static func stableID(_ name: String, _ latitude: Double, _ longitude: Double) -> String {
        let folded = name.replacingOccurrences(of: " ", with: "")
        return String(format: "%@-%.3f-%.3f", folded, latitude, longitude)
    }
}
