import Foundation
import WidgetKit
import SwiftData
import RitmoCore

@MainActor
final class WatchViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var sleepSession: SleepSession? = nil   // primary (longest) — used by recovery score
    @Published var sleepSessions: [SleepSession] = []  // all sessions for the night
    @Published var recovery: RecoveryScore? = nil
    /// iPhone-computed training load, when available (the source of truth —
    /// see HealthKitRepository.cacheTrainingLoad). Nil until the iPhone has synced.
    @Published var trainingLoad: TrainingLoad? = nil
    /// iPhone-computed daily recommendation — same source-of-truth rule.
    @Published var phoneRecommendation: DailyRecommendation? = nil

    private let healthRepo = HealthKitRepository()

    func load(goals: UserGoals) async {
        await healthRepo.requestAuthorization()

        // Watch is self-sufficient for HealthKit workouts: import them straight
        // into the watch store so the workout tab fills with no phone dependency.
        await healthRepo.importHealthKitWorkouts(into: RitmoStore.container.mainContext)

        async let snapshotResult  = healthRepo.fetchDailySnapshot(for: .now, goals: goals)
        async let allSleepResult  = healthRepo.fetchAllSleepSessions(for: .now)
        async let activityResult  = healthRepo.fetchDailyActivity(for: .now)
        async let recoveryResult  = healthRepo.fetchRecovery()
        snapshot      = await snapshotResult
        sleepSessions = await allSleepResult
        activity      = await activityResult
        recovery      = await recoveryResult
        sleepSession  = sleepSessions.max(by: { $0.totalHours < $1.totalHours })
        trainingLoad  = HealthKitRepository.cachedTrainingLoad()
        phoneRecommendation = HealthKitRepository.cachedDailyRecommendation()
        persistSnapshot(snapshot)
    }

    private func persistSnapshot(_ snapshot: DailySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo")
        else { return }
        defaults.set(data, forKey: "dailySnapshot")

        // Last workout date, for the days-since complication.
        let latest = (try? RitmoStore.container.mainContext.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        ))?.first?.startTime
        defaults.set(latest?.timeIntervalSince1970 ?? 0, forKey: "lastWorkoutDate")

        WidgetCenter.shared.reloadTimelines(ofKind: "RitmoWatchWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "RitmoDaysSinceWorkout")
    }
}
