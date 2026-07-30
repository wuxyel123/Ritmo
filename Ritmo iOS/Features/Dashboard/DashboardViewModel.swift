import Foundation
import SwiftData
import RitmoCore

@MainActor
final class DashboardViewModel: ObservableObject {
    // Empty, NOT .placeholder: the placeholder carries invented numbers for
    // the widget gallery (7200 steps, 5.4 km, 8 floors…). Starting from it
    // flashed that fiction on the home screen until HealthKit answered.
    @Published var snapshot = DailySnapshot()
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var lastSession: WorkoutSession?
    @Published var topInsight: FitInsight?
    @Published var recovery: RecoveryScore?
    @Published var weeklyRecap: WeeklyRecap?
    @Published var isLoading = false

    private let insightsService = InsightsService()

    func refresh(for date: Date = .now, healthRepo: HealthKitRepository, modelContext: ModelContext, goals: UserGoals) async {
        isLoading = true
        defer { isLoading = false }

        let isToday = Calendar.current.isDateInToday(date)
        async let snap = healthRepo.fetchDailySnapshot(for: date, goals: goals)
        async let act  = healthRepo.fetchDailyActivity(for: date)
        snapshot = await snap
        activity = await act
        // Recovery is a "today" readiness metric only
        recovery = isToday ? await healthRepo.fetchRecovery() : nil

        // Only cache today's snapshot for widgets
        if isToday {
            saveSnapshotForWidgets(snapshot)
        }

        // Latest workout for dashboard card
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        lastSession = try? modelContext.fetch(descriptor).first

        // Weekly recap: fixed for the whole week, so compute it once per launch
        // (the 14-day sleep loop is the expensive part — don't re-run it on
        // every date change / pull-to-refresh).
        if weeklyRecap == nil, isToday {
            let allSessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            var sleepHistory: [SleepSession] = []
            for i in 0..<14 {
                if let d = Calendar.current.date(byAdding: .day, value: -i, to: .now),
                   let s = await healthRepo.fetchSleep(for: d) { sleepHistory.append(s) }
            }
            weeklyRecap = WeeklyRecap.compute(sessions: allSessions, sleepSessions: sleepHistory)
        }
    }

    func generateInsights(sessions: [WorkoutSession], nutritionHistory: [NutritionDay],
                          sleepHistory: [SleepSession], activityHistory: [DailyActivity],
                          goals: UserGoals) {
        let insights = insightsService.generateInsights(
            sessions: sessions,
            nutritionHistory: nutritionHistory,
            sleepHistory: sleepHistory,
            activityHistory: activityHistory,
            goals: goals
        )
        topInsight = insights.first
    }

    private func saveSnapshotForWidgets(_ snapshot: DailySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo")
        else { return }
        defaults.set(data, forKey: "dailySnapshot")
    }
}
