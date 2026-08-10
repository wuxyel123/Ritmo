import SwiftUI
import SwiftData
import RitmoCore

@main
struct RitmoWatchApp: App {
    init() {
        GoalsSyncService.shared.container = RitmoStore.container
    }

    var body: some Scene {
        WindowGroup {
            WatchTabView()
                .modelContainer(RitmoStore.container)
        }
    }
}

struct WatchTabView: View {
    @Query private var storedGoals: [UserGoals]
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @StateObject private var vm = WatchViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    private var goals: UserGoals { storedGoals.first ?? UserGoals() }

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchHomeView(goals: goals, sessions: sessions).tag(0)      // score + breakdown
            WatchMacroGoalsView(goals: goals).tag(1)                    // nutrition
            WatchWorkoutView(goals: goals, sessions: sessions).tag(2)   // workout
            WatchSleepView(goals: goals, sessions: sessions).tag(3)     // sleep
            WatchHealthView().tag(4)                                    // salute (HR, HRV, SpO₂)
            WatchWaterView(goals: goals, sessions: sessions).tag(5)     // water
        }
        #if os(watchOS)
        .tabViewStyle(.page)
        #endif
        .environmentObject(vm)
        .task { await reload() }
        // Refresh all HealthKit-derived data whenever the app comes to the
        // foreground (wrist raise / reopen) — goals already reload via onChange.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        // Reload snapshot when goals change
        .onChange(of: goals.dailyCalories)       { Task { await reload() } }
        .onChange(of: goals.dailyProteinG)       { Task { await reload() } }
        .onChange(of: goals.dailyWaterMl)        { Task { await reload() } }
        .onChange(of: goals.dailySteps)          { Task { await reload() } }
        .onChange(of: goals.dailyActiveCalories) { Task { await reload() } }
        // Immediate reload when goals arrive via WatchConnectivity
        .onReceive(NotificationCenter.default.publisher(for: .goalsSyncDidUpdate)) { _ in
            Task { await reload() }
        }
    }

    /// Loads using the canonical goals read straight from the shared store, so
    /// scoring never runs against a stale @Query snapshot or a duplicate record.
    @MainActor
    private func reload() async {
        let canonical = UserGoals.canonical(in: RitmoStore.container.mainContext)
        try? RitmoStore.container.mainContext.save()
        await vm.load(goals: canonical)
    }
}
