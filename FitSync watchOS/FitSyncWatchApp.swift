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
            WatchHomeView(goals: goals, sessions: sessions)      // 1 — score + breakdown (merged)
            WatchMacroGoalsView(goals: goals)                    // 2 — nutrition
            WatchWorkoutView(goals: goals, sessions: sessions)   // 3 — workout
            WatchSleepView(goals: goals, sessions: sessions)     // 4 — sleep
            WatchWaterView(goals: goals, sessions: sessions)     // 5 — water (last)
        }
        #if os(watchOS)
        .tabViewStyle(.page)
        #endif
        .environmentObject(vm)
        .task { await vm.load(goals: goals, sessions: sessions) }
        // Reload snapshot when goals change (CloudKit or local mutation)
        .onChange(of: goals.dailyCalories)       { Task { await vm.load(goals: goals, sessions: sessions) } }
        .onChange(of: goals.dailyProteinG)       { Task { await vm.load(goals: goals, sessions: sessions) } }
        .onChange(of: goals.dailyWaterMl)        { Task { await vm.load(goals: goals, sessions: sessions) } }
        .onChange(of: goals.dailySteps)          { Task { await vm.load(goals: goals, sessions: sessions) } }
        .onChange(of: goals.dailyActiveCalories) { Task { await vm.load(goals: goals, sessions: sessions) } }
        // Immediate reload when goals arrive via WatchConnectivity
        .onReceive(NotificationCenter.default.publisher(for: .goalsSyncDidUpdate)) { _ in
            Task { await vm.load(goals: goals, sessions: sessions) }
        }
    }
}
