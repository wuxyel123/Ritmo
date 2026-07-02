import SwiftUI
import SwiftData
import RitmoCore

// MARK: - iOS App Entry Point
@main
struct RitmoApp: App {
    @StateObject private var langManager = LanguageManager()
    @StateObject private var healthRepo = HealthKitRepository()

    init() {
        _ = GoalsSyncService.shared  // activate WCSession early
        // Re-registers the App Shortcuts with Siri/Spotlight on every launch —
        // without this, dev builds often never surface them to Siri.
        RitmoShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(RitmoStore.container)
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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var storedGoals: [UserGoals]
    @State private var selectedTab = 0

    private var goals: UserGoals { storedGoals.first ?? UserGoals() }

    private func pushGoals() {
        let ctx = RitmoStore.container.mainContext
        let canonical = UserGoals.canonical(in: ctx)
        try? ctx.save()
        GoalsSyncService.shared.send(canonical)
    }

    /// Re-imports HealthKit workouts (deduping stale/duplicate entries), then
    /// pushes the exclusion set + freshly computed training load to the Watch —
    /// the iPhone is the source of truth for both, so the two devices agree.
    private func syncWorkoutsToWatch() async {
        let ctx = RitmoStore.container.mainContext
        await healthRepo.importHealthKitWorkouts(into: ctx)
        GoalsSyncService.shared.sendExcludedWorkouts(Array(HealthKitRepository.excludedWorkoutUUIDs()))
        let fresh = (try? ctx.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        )) ?? []
        GoalsSyncService.shared.sendTrainingLoad(TrainingLoad.compute(from: fresh))
    }

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
        .tint(RitmoTheme.accent)
        .task {
            pushGoals()
            await syncWorkoutsToWatch()
        }
        // Force a push whenever goals change or the app returns to the foreground.
        .onChange(of: goals.syncSignature) { _, _ in pushGoals() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                pushGoals()
                Task { await syncWorkoutsToWatch() }
            }
        }
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
