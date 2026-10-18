import SwiftUI

// 아이폰은 아래 탭, 넓은 화면(맥·아이패드)은 왼쪽 목록으로 화면을 나눕니다.

struct AppShell: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                TabView {
                    MapScreen()
                        .tabItem { Label("지도", systemImage: "map") }
                    TackleLibraryView()
                        .tabItem { Label("채비", systemImage: "wrench.and.screwdriver") }
                    MyPointsView()
                        .tabItem { Label("내 포인트", systemImage: "mappin") }
                    SettingsView()
                        .tabItem { Label("설정", systemImage: "gearshape") }
                }
            } else {
                NavigationSplitView {
                    List {
                        NavigationLink { MapScreen() } label: { Label("지도", systemImage: "map") }
                        NavigationLink { TackleLibraryView() } label: { Label("채비도감", systemImage: "wrench.and.screwdriver") }
                        NavigationLink { MyPointsView() } label: { Label("내 포인트", systemImage: "mappin") }
                        NavigationLink { SettingsView() } label: { Label("설정", systemImage: "gearshape") }
                    }
                    .navigationTitle("바로낚시")
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                } detail: {
                    MapScreen()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { store.selectedPointId != nil },
            set: { if !$0 { store.selectedPointId = nil } }
        )) {
            if let id = store.selectedPointId {
                PointDetailView(pointId: id)
                    .environmentObject(store)
            }
        }
        .preferredColorScheme(.dark)
    }
}

@main
struct BaroNaksiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .onAppear { store.start() }
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("이 지역 다시 분석") { store.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
