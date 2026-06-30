import SwiftUI
import SwiftData
import FitSyncCore

// MARK: - iOS App Entry Point
@main
struct FitSyncApp: App {
    @StateObject private var langManager = LanguageManager()
    @StateObject private var healthRepo = HealthKitRepository()

    init() {
        _ = GoalsSyncService.shared  // activate WCSession early
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(FitSyncStore.container)
                .id(langManager.viewID)
                .environment(\.locale, langManager.locale)
                .environmentObject(langManager)
                .environmentObject(healthRepo)
                .task { await healthRepo.requestAuthorization() }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onNavigate: { selectedTab = $0 })
                .tabItem { Label("Oggi", systemImage: "house.fill") }.tag(0)

            WorkoutListView()
                .tabItem { Label("Allenamenti", systemImage: "dumbbell.fill") }.tag(1)

            NutritionView()
                .tabItem { Label("Nutrizione", systemImage: "fork.knife") }.tag(2)

            RecoveryView()
                .tabItem { Label("Recupero", systemImage: "bed.double.fill") }.tag(3)

            HealthView()
                .tabItem { Label("Salute", systemImage: "heart.fill") }.tag(4)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }.tag(5)

            SettingsTabView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }.tag(6)
        }
        .tint(FitSyncTheme.accent)
        .onOpenURL { url in
            switch url.host {
            case "nutrition": selectedTab = 2
            case "recovery":  selectedTab = 3
            case "health":    selectedTab = 4
            case "insights":  selectedTab = 5
            case "workouts":  selectedTab = 1
            default:          selectedTab = 0
            }
        }
    }
}
