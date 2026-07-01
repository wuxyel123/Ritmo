import SwiftUI
import SwiftData
import Charts
import RitmoCore

struct InsightsView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query private var storedGoals: [UserGoals]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @StateObject private var vm = InsightsViewModel()

    var goals: UserGoals { storedGoals.first ?? UserGoals() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RitmoTheme.gap) {

                    // How-it-works info banner
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Come funzionano gli Insights", systemImage: "brain.head.profile")
                                .font(.subheadline.bold()).foregroundStyle(RitmoTheme.accent)
                            Text("Gli insights analizzano automaticamente: bilancio muscolare (push/pull/gambe), variabilità del sonno, distribuzione delle proteine nei giorni di allenamento vs riposo, e correlazioni tra recupero e performance. Più dati hai (almeno 2 settimane), più sono accurati.")
                                .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                        }
                    }

                    if vm.isLoading {
                        ProgressView("Analizzando i tuoi dati…")
                            .padding(.vertical, 40)
                    } else if vm.insights.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 60)).foregroundStyle(RitmoTheme.accent.opacity(0.4))
                            Text("Nessun insight disponibile")
                                .font(.title3.bold())
                            Text("Registra almeno 2 settimane di allenamenti e collega il tuo food tracker ad Apple Salute per ricevere insights personalizzati.")
                                .font(.subheadline).foregroundStyle(RitmoTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }.padding(RitmoTheme.pagePadding)
                    } else {
                        // Insights sorted by priority
                        ForEach(vm.insights) { insight in InsightCard(insight: insight) }

                        // PR section
                        if !vm.topPRs.isEmpty {
                            FitCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Personal Records 🏆")
                                    ForEach(Array(vm.topPRs.prefix(8)), id: \.id) { pr in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pr.exerciseName).font(.subheadline.bold())
                                                Text(pr.achievedDate, style: .date)
                                                    .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(String(format: "%.1f kg × %d", pr.weightKg, pr.reps))
                                                    .font(.subheadline.bold())
                                                Text(String(format: "~%.0f kg 1RM", pr.estimatedOneRepMax))
                                                    .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                                            }
                                        }
                                        if pr.id != vm.topPRs.prefix(8).last?.id { Divider() }
                                    }
                                }
                            }
                        }

                        // Volume per muscle group (last 7 days)
                        if !vm.muscleVolume.isEmpty {
                            FitCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Volume — ultimi 7 giorni")
                                    Chart(vm.muscleVolume.sorted { $0.value > $1.value }, id: \.key) { item in
                                        BarMark(x: .value("kg", item.value / 1000),
                                                y: .value("Muscolo", item.key.rawValue))
                                            .foregroundStyle(RitmoTheme.workout)
                                            .cornerRadius(4)
                                    }
                                    .frame(height: CGFloat(vm.muscleVolume.count) * 28)
                                    .chartXAxisLabel("Volume (×1000 kg)")
                                }
                            }
                        }
                    }
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle("Insights")
            .task { await vm.load(healthRepo: healthRepo, sessions: sessions, goals: goals) }
        }
    }
}

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var insights: [FitInsight] = []
    @Published var topPRs: [PersonalRecord] = []
    @Published var muscleVolume: [MuscleGroup: Double] = [:]
    @Published var isLoading = false

    private let insightsService = InsightsService()
    private let prService = PRService()

    func load(healthRepo: HealthKitRepository, sessions: [WorkoutSession], goals: UserGoals) async {
        isLoading = true
        defer { isLoading = false }

        async let nutritionH = healthRepo.fetchNutritionHistory(days: 14)
        var sleepH: [SleepSession] = []
        for i in 0..<14 {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: .now),
               let s = await healthRepo.fetchSleep(for: d) { sleepH.append(s) }
        }

        var actH: [DailyActivity] = []
        await withTaskGroup(of: DailyActivity.self) { group in
            for i in 0..<14 {
                if let d = Calendar.current.date(byAdding: .day, value: -i, to: .now) {
                    group.addTask { await healthRepo.fetchDailyActivity(for: d) }
                }
            }
            for await a in group { actH.append(a) }
        }

        insights = insightsService.generateInsights(
            sessions: sessions,
            nutritionHistory: await nutritionH,
            sleepHistory: sleepH,
            activityHistory: actH,
            goals: goals
        )

        let prs = prService.calculateAllPRs(from: sessions)
        topPRs = Array(prs.values).sorted { $0.estimatedOneRepMax > $1.estimatedOneRepMax }
        muscleVolume = prService.volumeByMuscleGroup(from: sessions, days: 7)
    }
}
