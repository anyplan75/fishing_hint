import SwiftUI

// 지도와 점수 순 목록입니다. 내 주변, 저장한 지역, 찍은 자리를 여기서 고릅니다.

struct MapScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 860 {
                HStack(spacing: 0) {
                    mapLayer.frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        controls
                        if !store.ranked.isEmpty {
                            list
                        }
                    }
                    .frame(width: 380)
                }
            } else {
                VStack(spacing: 0) {
                    mapLayer.frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls
                    if !store.ranked.isEmpty {
                        list.frame(maxHeight: min(260, geo.size.height * 0.28))
                    }
                }
            }
        }
        .background(FieldColor.ink)
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
                    radiusKm: store.radiusKm,
                    flyToken: store.flyToken,
                    pins: pins,
                    onTap: { lat, lon in store.analyzeTap(latitude: lat, longitude: lon) },
                    onSelect: { store.select($0) },
                    onMove: { lat, lon in store.rememberMap(latitude: lat, longitude: lon) },
                    onMap: { store.noteMap(ok: $0) }
                )
            }
        }
    }

    private var pins: [MapPin] {
        store.ranked.map { briefing in
            MapPin(
                id: briefing.point.id,
                name: briefing.point.name,
                latitude: briefing.point.latitude,
                longitude: briefing.point.longitude,
                score: briefing.score,
                selected: briefing.point.id == store.selectedPointId
            )
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("지역, 방파제, 포구 검색", text: $query)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(FieldColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit { store.searchPlaces(query) }
                Button("찾기") { store.searchPlaces(query) }
                    .buttonStyle(FieldButton(fill: FieldColor.sea))
            }
            if !store.searchHits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.searchHits) { hit in
                        Button(hit.name) { store.go(to: hit); query = hit.name }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .foregroundStyle(FieldColor.paper)
                    }
                }
                .background(FieldColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if store.mapboxToken.isEmpty {
                Text("설정에서 맵박스 암호를 넣으면 지도가 켜집니다.")
                    .font(.caption)
                    .foregroundStyle(FieldColor.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("반경 \(Int(store.radiusKm))km")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FieldColor.good)
                    .lineLimit(1)
                Slider(value: $store.radiusKm, in: 3...30, step: 1, onEditingChanged: { editing in
                    if !editing { store.refresh() }
                })
                Button(store.busy ? "계산 중" : "이 지역 분석") { store.refresh() }
                    .buttonStyle(FieldButton(fill: FieldColor.good, ink: FieldColor.ink))
                    .disabled(store.busy)
            }
            HStack {
                Button("내 위치") { store.focusOnMe() }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
                Button("저장 지역") { store.useSavedRegion() }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
                Button("이 지역 저장") { store.saveCurrentRegion() }
                    .buttonStyle(FieldButton(fill: FieldColor.card2))
                Spacer(minLength: 0)
            }
            Text("\(store.useMyLocation ? "내 주변" : store.regionTitle) · \(store.locationText)")
                .font(.caption2)
                .foregroundStyle(FieldColor.muted)
                .lineLimit(1)
            linkRow("지도", store.mapLink)
            linkRow("인공지능", store.aiLink)
            linkRow("조석", store.tideLink)
            Text(store.statusText)
                .font(.caption)
                .foregroundStyle(FieldColor.paper)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
    }

    private func linkRow(_ title: String, _ link: LinkLine) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                Text(link.word)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(link.connected ? FieldColor.good : FieldColor.bad)
            }
            if !link.connected {
                Text(link.reason)
                    .font(.caption2)
                    .foregroundStyle(FieldColor.muted)
                    .lineLimit(1)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.regionTitle)
                    .font(.headline)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.ranked) { briefing in
                        Button { store.select(briefing.point.id) } label: {
                            PointRankCard(briefing: briefing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(FieldColor.ink)
        .foregroundStyle(FieldColor.paper)
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
                .lineLimit(2)
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
