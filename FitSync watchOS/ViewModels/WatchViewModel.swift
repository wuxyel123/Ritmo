import Foundation
import WidgetKit
import SwiftData
import FitSyncCore

@MainActor
final class WatchViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var sleepSession: SleepSession? = nil   // primary (longest) — used by recovery score
    @Published var sleepSessions: [SleepSession] = []  // all sessions for the night

    private let healthRepo = HealthKitRepository()

    func load(goals: UserGoals) async {
        await healthRepo.requestAuthorization()

        // Watch is self-sufficient for HealthKit workouts: import them straight
        // into the watch store so the workout tab fills with no phone dependency.
        await healthRepo.importHealthKitWorkouts(into: FitSyncStore.container.mainContext)

        async let snapshotResult  = healthRepo.fetchDailySnapshot(for: .now, goals: goals)
        async let allSleepResult  = healthRepo.fetchAllSleepSessions(for: .now)
        async let activityResult  = healthRepo.fetchDailyActivity(for: .now)
        snapshot      = await snapshotResult
        sleepSessions = await allSleepResult
        activity      = await activityResult
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
