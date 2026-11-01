import SwiftUI

// 아이폰은 아래 탭, 넓은 화면(맥·아이패드)은 왼쪽 목록으로 화면을 나눕니다.

struct AppShell: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var phoneTab = 0

    var body: some View {
        Group {
            if sizeClass == .compact {
                TabView(selection: $phoneTab) {
                    MapScreen()
                        .tabItem { Label("지도", systemImage: "map") }
                        .tag(0)
                    ChartScreen()
                        .tabItem { Label("바다해도", systemImage: "water.waves") }
                        .tag(1)
                    RecommendScreen()
                        .tabItem { Label("추천", systemImage: "star.circle") }
                        .tag(2)
                    PublicFishingScreen()
                        .tabItem { Label("낚시글", systemImage: "doc.text") }
                        .tag(3)
                    TackleLibraryView()
                        .tabItem { Label("채비", systemImage: "wrench.and.screwdriver") }
                        .tag(4)
                    MyPointsView()
                        .tabItem { Label("내 포인트", systemImage: "mappin") }
                        .tag(5)
                    SettingsView()
                        .tabItem { Label("설정", systemImage: "gearshape") }
                        .tag(6)
                }
                .onChange(of: phoneTab) { newValue in
                    if newValue == 3 { PublicFishingBoard.shared.refreshIfNeeded() }
                }
            } else {
                NavigationView {
                    List {
                        NavigationLink { MapScreen() } label: { Label("지도", systemImage: "map") }
                        NavigationLink { ChartScreen() } label: { Label("바다해도", systemImage: "water.waves") }
                        NavigationLink { RecommendScreen() } label: { Label("추천", systemImage: "star.circle") }
                        NavigationLink { PublicFishingScreen() } label: { Label("낚시글", systemImage: "doc.text") }
                        NavigationLink { TackleLibraryView() } label: { Label("채비도감", systemImage: "wrench.and.screwdriver") }
                        NavigationLink { MyPointsView() } label: { Label("내 포인트", systemImage: "mappin") }
                        NavigationLink { SettingsView() } label: { Label("설정", systemImage: "gearshape") }
                    }
                    .navigationTitle("바로낚시")
                    .frame(minWidth: 180, idealWidth: 210)
                    MapScreen()
                }
                .navigationViewStyle(DoubleColumnNavigationViewStyle())
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
        .onChange(of: scenePhase) { phase in
            if phase == .active { PublicFishingBoard.shared.refreshIfNeeded() }
        }
    }
}

@main
struct BaroNaksiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    PublicFishingBoard.shared.refreshIfNeeded()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        #endif
        .commands {
            CommandGroup(after: .newItem) {
                Button("이 지역 다시 분석") { store.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
