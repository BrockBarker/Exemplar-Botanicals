import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \GardenProfile.created) private var profiles: [GardenProfile]

    var body: some View {
        Group {
            if let profile = profiles.first, profile.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Color.accentColor)
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            CoachView()
                .tabItem { Label(app.coachName, systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.coach)
            DiagnoseView()
                .tabItem { Label("Photo check", systemImage: "camera.viewfinder") }
                .tag(AppTab.diagnose)
            GardenView()
                .tabItem { Label("Garden", systemImage: "leaf.fill") }
                .tag(AppTab.garden)
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(AppTab.journal)
        }
    }
}
