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
                            Text("Gli insights analizzano automaticamente: bilancio muscolare (push/pull/gambe), carico di allenamento (acuto/cronico), variabilità del sonno, distribuzione delle proteine nei giorni di allenamento vs riposo, e correlazioni tra recupero e performance. Più dati hai (almeno 2 settimane), più sono accurati.")
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

                        // Load / sleep / HRV on one time axis — raw series,
                        // aligned so patterns are visible without any verdict.
                        CorrelationCard()

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

// MARK: - CorrelationCard (load · sleep · HRV, 30 days, shared time axis)

struct CorrelationCard: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]

    @State private var loadDaily: [DateValuePoint] = []
    @State private var sleepDaily: [DateValuePoint] = []
    @State private var hrvDaily: [DateValuePoint] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded, !loadDaily.isEmpty || !sleepDaily.isEmpty || !hrvDaily.isEmpty {
                FitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Carico · Sonno · HRV")
                        Text("Ultimi 30 giorni sullo stesso asse temporale")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !loadDaily.isEmpty {
                            miniChart(title: "Carico", points: loadDaily,
                                      color: RitmoTheme.workout, isBar: true, unit: "")
                        }
                        if !sleepDaily.isEmpty {
                            miniChart(title: "Sonno (ore)", points: sleepDaily,
                                      color: .indigo, isBar: false, unit: " h", decimals: 1)
                        }
                        if !hrvDaily.isEmpty {
                            miniChart(title: "HRV (ms)", points: hrvDaily,
                                      color: .green, isBar: false, unit: " ms")
                        }
                    }
                }
            }
        }
        .task {
            guard !loaded else { return }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)

            // Daily training load (session-RPE), zero-filled days included so
            // the three charts share the same 30-day span.
            var byDay: [Date: Double] = [:]
            if let cutoff = calendar.date(byAdding: .day, value: -29, to: today) {
                for session in sessions where session.startTime >= cutoff {
                    byDay[calendar.startOfDay(for: session.startTime), default: 0] += session.loadValue
                }
                loadDaily = (0..<30).compactMap { offset in
                    calendar.date(byAdding: .day, value: -29 + offset, to: today).map {
                        DateValuePoint(date: $0, value: byDay[$0] ?? 0)
                    }
                }
                if byDay.isEmpty { loadDaily = [] }
            }

            // Sleep hours per night (same per-day fetch the recovery tab uses).
            var sleep: [DateValuePoint] = []
            for offset in 0..<30 {
                if let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                   let session = await healthRepo.fetchSleep(for: day) {
                    sleep.append(DateValuePoint(date: calendar.startOfDay(for: day),
                                                value: min(session.totalHours, 14)))
                }
            }
            sleepDaily = sleep.sorted { $0.date < $1.date }

            hrvDaily = await healthRepo.fetchHRVHistory(days: 30)
            loaded = true
        }
    }

    private func miniChart(title: String, points: [DateValuePoint], color: Color,
                           isBar: Bool, unit: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.caption2.bold()).foregroundStyle(color)
            SelectableStatChart(points: points, isBar: isBar, barWidth: 5,
                                color: color, decimals: decimals, unit: unit, height: 70)
        }
    }
}
