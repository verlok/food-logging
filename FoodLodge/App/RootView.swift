import SwiftUI

/// Shows onboarding until the profile is set up, then the main tabs.
struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.profile.onboardingCompleted {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DiaryView()
                .tabItem { Label("Diary", systemImage: "fork.knife") }
            FoodLibraryView()
                .tabItem { Label("Foods", systemImage: "carrot.fill") }
            WeightView()
                .tabItem { Label("Weight", systemImage: "scalemass.fill") }
            ChartsView()
                .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
