import SwiftUI

// 지도가 화면의 대부분입니다. 빈 곳의 왼쪽 클릭과 짧은 탭은 지도를 옮길 때만 씁니다.
// 이름과 성공률 글자를 누르면 그 포인트 정보가 바로 열립니다.
// 장소 저장은 오른쪽 클릭이나 길게 누르기에서 이름을 물은 뒤에만 합니다.

struct MapScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var infoOpen = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                mapLayer
                    .frame(width: geo.size.width, height: geo.size.height)
                VStack(spacing: 8) {
                    searchBar
                    radiusBar
                    if !store.searchHits.isEmpty && !infoOpen {
                        searchRow
                            .padding(8)
                            .background(FieldColor.ink.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    if infoOpen {
                        infoCard(height: min(geo.size.height * 0.56, 460))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        .background(FieldColor.ink)
        .sheet(item: $store.savePrompt, onDismiss: { store.noteNamePromptClosed() }) { prompt in
            NameSaveSheet(point: prompt.point)
        }
    }

    private var mapLayer: some View {
        Group {
            if store.mapboxToken.isEmpty {
                FieldColor.card
            } else {
                MapboxMapView(
                    token: store.mapboxToken,
                    latitude: store.centerLat,
                    longitude: store.centerLon,
                    userLat: store.userLat,
                    userLon: store.userLon,
                    circleLat: store.circleAnchor?.latitude,
                    circleLon: store.circleAnchor?.longitude,
                    radiusKm: store.radiusKm,
                    flyToken: store.flyToken,
                    fitToken: store.mapFit,
                    route: store.routeLine,
                    pins: pins,
                    onSave: { lat, lon in
                        store.askPlaceName(latitude: lat, longitude: lon)
                    },
                    onSelect: { id in
                        infoOpen = true
                        store.select(id)
                    },
                    onMove: { lat, lon in store.rememberMap(latitude: lat, longitude: lon) },
                    onMap: { store.noteMap(ok: $0) }
                )
            }
        }
    }

    private var pins: [MapPin] {
        var items: [MapPin] = []
        for briefing in store.ranked {
            guard store.isInsideCircle(latitude: briefing.point.latitude, longitude: briefing.point.longitude) else { continue }
            items.append(MapPin(
                id: briefing.point.id,
                name: briefing.point.name,
                latitude: briefing.point.latitude,
                longitude: briefing.point.longitude,
                score: briefing.score,
                selected: briefing.point.id == store.selectedPointId,
                label: fishingLabel(name: briefing.point.name, score: briefing.score)
            ))
        }
        for point in store.myPoints where point.isMine && !items.contains(where: { $0.id == point.id }) {
            items.append(MapPin(
                id: point.id,
                name: point.name,
                latitude: point.latitude,
                longitude: point.longitude,
                score: -1,
                selected: point.id == store.selectedPointId
            ))
        }
        for hit in store.searchHits where !items.contains(where: { $0.id == "search-\(hit.id)" }) {
            items.append(MapPin(
                id: "search-\(hit.id)",
                name: hit.title,
                latitude: hit.latitude,
                longitude: hit.longitude,
                score: -1,
                selected: hit.id == store.selectedSearchId,
                marker: hit.marker
            ))
        }
        if let destination = store.destination {
            let shown = items.contains { $0.id == destination.id || $0.id == "search-\(destination.id)" }
            if !shown {
                items.append(MapPin(
                    id: "search-\(destination.id)",
                    name: destination.title,
                    latitude: destination.latitude,
                    longitude: destination.longitude,
                    score: -1,
                    selected: true,
                    marker: destination.marker
                ))
            }
        }
        return items
    }

    /// 검색으로 점수가 있는 낚시 핀만 이름과 성공률을 적습니다. 없는 성공률은 만들지 않습니다.
    private func fishingLabel(name: String, score: Int) -> String {
        guard score >= 0 else { return "" }
        return "\(name)\n성공률 \(score)%"
    }

    private var placeTitle: String {
        if store.savePrompt != nil, let tapped = store.tapped, !tapped.name.isEmpty {
            return tapped.name
        }
        if let destination = store.destination, !destination.title.isEmpty {
            return destination.title
        }
        if !store.regionTitle.isEmpty {
            return store.regionTitle
        }
        return "고른 자리"
    }

    /// 지도 위에 얇게 두는 반경 조절입니다. 분석 카드 안의 조절과 같은 값을 씁니다.
    private var radiusBar: some View {
        HStack(spacing: 8) {
            Text("반경 \(Int(store.radiusKm))km")
                .font(.caption.weight(.bold))
                .foregroundStyle(FieldColor.good)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            Slider(value: $store.radiusKm, in: 3...30, step: 1, onEditingChanged: { editing in
                if !editing { store.refresh() }
            })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(FieldColor.ink.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("지역, 식당, 숙소 검색", text: $query)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(FieldColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit { store.searchPlaces(query) }
                Button("찾기") { store.searchPlaces(query) }
                    .buttonStyle(FieldButton(fill: FieldColor.sea))
                Button(store.busy ? "계산 중" : "분석") {
                    infoOpen = true
                    store.refresh()
                }
                    .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                    .disabled(store.busy)
                Button("내 위치") { store.focusOnMe() }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
            }
            if store.mapboxToken.isEmpty {
                Text("지도 없음. 비밀 파일에 MAPBOX_ACCESS_TOKEN 이 없습니다.")
                    .font(.caption2)
                    .foregroundStyle(FieldColor.muted)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(FieldColor.ink.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(FieldColor.paper)
    }

    /// 분석이 카드 맨 위에 바로 보입니다. 목록이 길면 이 카드 안에서만 올립니다.
    private func infoCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(placeTitle)
                    .font(.headline)
                    .foregroundStyle(FieldColor.paper)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("닫기") { infoOpen = false }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
            }
            Text("분석")
                .font(.caption.weight(.bold))
                .foregroundStyle(FieldColor.good)
            analysisPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text(store.routeNote.isEmpty ? "경로 없음" : store.routeNote)
                .font(.caption)
                .foregroundStyle(FieldColor.paper)
                .lineLimit(1)
            searchRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height)
        .background(FieldColor.ink.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FieldColor.line, lineWidth: 1))
        .foregroundStyle(FieldColor.paper)
    }

    private var analysisPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.ranked.isEmpty {
                    Text(store.busy ? "이 지역을 계산하는 중" : "분석 없음. 분석 버튼으로 이 지역을 계산합니다.")
                        .font(.subheadline)
                        .foregroundStyle(FieldColor.paper)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(FieldColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    ForEach(store.ranked) { briefing in
                        Button { store.select(briefing.point.id) } label: {
                            PointRankCard(briefing: briefing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Text("반경 \(Int(store.radiusKm))km")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FieldColor.good)
                        .lineLimit(1)
                    Slider(value: $store.radiusKm, in: 3...30, step: 1, onEditingChanged: { editing in
                        if !editing { store.refresh() }
                    })
                }
                HStack {
                    Button("길 안내") { store.guideChosen() }
                        .buttonStyle(FieldButton(fill: FieldColor.sea))
                    Button("저장 지역") { store.useSavedRegion() }
                        .buttonStyle(FieldButton(fill: FieldColor.card2))
                    Button("이 지역 저장") { store.saveCurrentRegion() }
                        .buttonStyle(FieldButton(fill: FieldColor.card2))
                    Spacer(minLength: 0)
                }
                if !store.roadNote.isEmpty {
                    Text(store.roadNote)
                        .font(.caption2)
                        .foregroundStyle(FieldColor.muted)
                        .lineLimit(1)
                }
            }
        }
    }

    private var searchRow: some View {
        Group {
            if store.searchHits.isEmpty {
                Text("검색 결과 없음")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.searchHits) { hit in
                            Button(hit.title) {
                                infoOpen = true
                                store.openSearch(hit.id)
                                query = hit.title
                            }
                            .buttonStyle(FieldButton(fill: FieldColor.card))
                        }
                    }
                }
                .frame(height: 36)
            }
        }
    }
}

struct PointRankCard: View {
    var briefing: PointBriefing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(briefing.call.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.call(briefing.call).opacity(0.18))
                    .foregroundStyle(Color.call(briefing.call))
                    .clipShape(Capsule())
                Spacer()
                Text("\(briefing.score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.call(briefing.call))
            }
            Text(briefing.point.name)
                .font(.headline)
                .foregroundStyle(FieldColor.paper)
            Text(briefing.headline)
                .font(.subheadline)
                .foregroundStyle(FieldColor.paper)
            HStack {
                Text(briefing.point.place.title)
                if let distance = briefing.distanceKm {
                    Text(FieldFormat.distance(distance))
                }
                if briefing.point.isMine { Text("내 포인트") }
            }
            .font(.caption)
            .foregroundStyle(FieldColor.muted)
            Text(briefing.nowLine)
                .font(.caption)
                .foregroundStyle(FieldColor.muted)
            if !briefing.conditionLines.isEmpty {
                ForEach(Array(briefing.conditionLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(FieldColor.paper)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldColor.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FieldColor.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FieldButton: ButtonStyle {
    var fill: Color
    var ink: Color = FieldColor.paper

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(ink)
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
