import Foundation
import SwiftData
import FitSyncCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder
    @Published var lastSession: WorkoutSession?
    @Published var topInsight: FitInsight?
    @Published var isLoading = false

    private let insightsService = InsightsService()

    func refresh(for date: Date = .now, healthRepo: HealthKitRepository, modelContext: ModelContext, goals: UserGoals) async {
        isLoading = true
        defer { isLoading = false }

        // Check SwiftData for Hevy/manual workouts on this date (HK won't see these)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let allSessions = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let hasHevyWorkout = allSessions.contains {
            $0.source == .hevy && $0.startTime >= start && $0.startTime < end
        }

        snapshot = await healthRepo.fetchDailySnapshot(for: date, goals: goals, hasHevyWorkout: hasHevyWorkout)

        // Only cache today's snapshot for widgets
        if calendar.isDateInToday(date) {
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
