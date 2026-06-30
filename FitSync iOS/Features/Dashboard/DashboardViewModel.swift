import Foundation
import SwiftData
import FitSyncCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var lastSession: WorkoutSession?
    @Published var topInsight: FitInsight?
    @Published var recovery: RecoveryScore?
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
              let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.fitsync")
        else { return }
        defaults.set(data, forKey: "dailySnapshot")
    }
}
