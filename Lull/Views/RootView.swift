import SwiftUI
import LullCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.hasProfile {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.accent(isSleeping: model.isSleeping))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshAfterForeground() }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            presenting: model.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Now", systemImage: "moon.zzz.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
            InsightsView()
                .tabItem { Label("Patterns", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
