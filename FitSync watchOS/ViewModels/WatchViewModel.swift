import Foundation
import WidgetKit
import FitSyncCore

@MainActor
final class WatchViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder
    @Published var sleepSession: SleepSession? = nil   // primary (longest) — used by recovery score
    @Published var sleepSessions: [SleepSession] = []  // all sessions for the night

    private let healthRepo = HealthKitRepository()

    func load(goals: UserGoals, sessions: [WorkoutSession]) async {
        await healthRepo.requestAuthorization()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let hasHevyWorkout = sessions.contains { $0.source == .hevy && $0.startTime >= start && $0.startTime < end }
        async let snapshotResult  = healthRepo.fetchDailySnapshot(for: .now, goals: goals, hasHevyWorkout: hasHevyWorkout)
        async let allSleepResult  = healthRepo.fetchAllSleepSessions(for: .now)
        snapshot      = await snapshotResult
        sleepSessions = await allSleepResult
        sleepSession  = sleepSessions.max(by: { $0.totalHours < $1.totalHours })
        persistSnapshot(snapshot)
    }

    private func persistSnapshot(_ snapshot: DailySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.fitsync")
        else { return }
        defaults.set(data, forKey: "dailySnapshot")
        WidgetCenter.shared.reloadTimelines(ofKind: "FitSyncWatchWidget")
    }
}
