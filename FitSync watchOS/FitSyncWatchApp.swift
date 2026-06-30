import SwiftUI
import SwiftData
import FitSyncCore

@main
struct FitSyncWatchApp: App {
    init() {
        GoalsSyncService.shared.container = FitSyncStore.container
    }

    var body: some Scene {
        WindowGroup {
            WatchTabView()
                .modelContainer(FitSyncStore.container)
        }
    }
}

struct WatchTabView: View {
    @Query private var storedGoals: [UserGoals]
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @StateObject private var vm = WatchViewModel()

    private var goals: UserGoals { storedGoals.first ?? UserGoals() }

    var body: some View {
        TabView {
            WatchHomeView(goals: goals, sessions: sessions)      // 1 — score + breakdown
            WatchMacroGoalsView(goals: goals)                    // 2 — nutrition
            WatchWorkoutView(goals: goals, sessions: sessions)   // 3 — workout
            WatchSleepView(goals: goals, sessions: sessions)     // 4 — sleep
            WatchHealthView()                                    // 5 — salute (HR, HRV, SpO₂)
            WatchWaterView(goals: goals, sessions: sessions)     // 6 — water
        }
        #if os(watchOS)
        .tabViewStyle(.page)
        #endif
        .environmentObject(vm)
        .task { await reload() }
        // Reload snapshot when goals change (CloudKit or local mutation)
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
        let canonical = UserGoals.canonical(in: FitSyncStore.container.mainContext)
        try? FitSyncStore.container.mainContext.save()
        await vm.load(goals: canonical)
    }
}
