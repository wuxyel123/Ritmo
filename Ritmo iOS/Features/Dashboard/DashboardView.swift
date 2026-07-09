import SwiftUI
import SwiftData
import RitmoCore

struct DashboardView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var storedGoals: [UserGoals]
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @StateObject private var vm = DashboardViewModel()
    @State private var selectedDate = Date.now
    @State private var showingCaloriesDetail = false
    @State private var showingStepsDetail = false
    var onNavigate: ((Int) -> Void)? = nil

    var goals: UserGoals { storedGoals.first ?? UserGoals() }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var trainingLoad: TrainingLoad { TrainingLoad.compute(from: sessions) }

    /// Today-only actionable headline: recovery 0 means "no data" (watch not
    /// worn at night), not a real score, so it's passed as nil.
    private var dailyPlan: DailyRecommendation? {
        guard isToday else { return nil }
        let usableRecovery = vm.recovery.flatMap { $0.overall > 0 ? $0 : nil }
        return DailyRecommendation.compute(recovery: usableRecovery,
                                           load: sessions.isEmpty ? nil : trainingLoad,
                                           hasWorkedOutToday: vm.snapshot.hasWorkedOutToday,
                                           sessions: sessions,
                                           weeklyWorkoutGoal: goals.weeklyWorkouts)
    }

    private func planColor(_ kind: DailyRecommendation.Kind) -> Color {
        switch kind {
        case .push:     return .green
        case .maintain: return RitmoTheme.accent
        case .easy:     return .orange
        case .rest:     return .red
        case .done:     return .teal
        }
    }

    private func recapStat(value: String, label: LocalizedStringKey,
                           delta: Double?, deltaIsPercent: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold())
            Text(label).font(.system(size: 9)).foregroundStyle(RitmoTheme.textSecondary)
            if let delta, delta != 0 {
                HStack(spacing: 2) {
                    Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(deltaIsPercent ? "\(abs(Int(delta.rounded())))%" : "\(abs(Int(delta)))")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(delta > 0 ? .green : .orange)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func recoveryColor(_ s: RecoveryStatus) -> Color {
        switch s {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .excellent: return .green
        }
    }

    private func loadColor(_ s: TrainingLoadStatus) -> Color {
        switch s {
        case .low: return .blue
        case .optimal: return .green
        case .high: return .orange
        case .veryHigh: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RitmoTheme.gap) {

                    // MARK: Navigazione date
                    DateNavigationBar(
                        selectedDate: $selectedDate,
                        isToday: isToday,
                        onDateChanged: { refresh() },
                        healthRepo: healthRepo
                    )

                    // MARK: Score del giorno
                    DayScoreCard(snapshot: vm.snapshot)

                    // MARK: Consiglio del giorno
                    if let plan = dailyPlan {
                        FitCard {
                            HStack(spacing: 12) {
                                Image(systemName: plan.kind.icon)
                                    .font(.title3)
                                    .foregroundStyle(planColor(plan.kind))
                                    .frame(width: 42, height: 42)
                                    .background(planColor(plan.kind).opacity(0.15), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey(plan.kind.title))
                                        .font(.headline)
                                        .foregroundStyle(planColor(plan.kind))
                                    Text(LocalizedStringKey(plan.reason))
                                        .font(.caption)
                                        .foregroundStyle(RitmoTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                        }
                    }

                    // MARK: Macro veloci
                    Button { onNavigate?(2) } label: {
                        FitCard {
                            VStack(spacing: 12) {
                                HStack {
                                    SectionHeader(title: "Nutrizione oggi")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                MacroRow(emoji: "🔥", label: "Calorie",
                                         current: vm.snapshot.calories, goal: vm.snapshot.calorieGoal,
                                         unit: "kcal", color: RitmoTheme.calories)
                                MacroRow(emoji: "🥩", label: "Proteine",
                                         current: vm.snapshot.protein, goal: vm.snapshot.proteinGoal,
                                         unit: "g", color: RitmoTheme.protein)
                                MacroRow(emoji: "🍞", label: "Carboidrati",
                                         current: vm.snapshot.carbs, goal: vm.snapshot.carbsGoal,
                                         unit: "g", color: RitmoTheme.carbs)
                                MacroRow(emoji: "🥑", label: "Grassi",
                                         current: vm.snapshot.fat, goal: vm.snapshot.fatGoal,
                                         unit: "g", color: RitmoTheme.fat)
                                MacroRow(emoji: "💧", label: "Acqua",
                                         current: vm.snapshot.waterMl / 1000, goal: vm.snapshot.waterGoal / 1000,
                                         unit: "L", color: RitmoTheme.water,
                                         fractionDigits: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: Attività (Move / Steps / Sleep / Salute)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: RitmoTheme.gap) {
                        Button { showingCaloriesDetail = true } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label("Calorie attive", systemImage: "bolt.fill")
                                            .font(.caption).foregroundStyle(.red)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Text("\(Int(vm.snapshot.activeCalories))")
                                        .font(.title2.bold())
                                    Text("su \(Int(vm.snapshot.activeCalorieGoal)) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(RitmoTheme.textSecondary)
                                    FitProgressBar(
                                        value: vm.snapshot.activeCalories / max(vm.snapshot.activeCalorieGoal, 1),
                                        color: .red
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingCaloriesDetail) {
                            ActivityMetricDetailView(metric: .activeCalories)
                        }
                        Button { showingStepsDetail = true } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label("Passi", systemImage: "figure.walk")
                                            .font(.caption).foregroundStyle(RitmoTheme.steps)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Text(vm.snapshot.steps.formatted())
                                        .font(.title2.bold())
                                    Text("su \(vm.snapshot.stepGoal.formatted())")
                                        .font(.caption2)
                                        .foregroundStyle(RitmoTheme.textSecondary)
                                    FitProgressBar(
                                        value: Double(vm.snapshot.steps) / Double(max(vm.snapshot.stepGoal, 1)),
                                        color: RitmoTheme.steps
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingStepsDetail) {
                            ActivityMetricDetailView(metric: .steps)
                        }
                        Button { onNavigate?(3) } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label("Sonno", systemImage: "bed.double.fill")
                                            .font(.caption).foregroundStyle(RitmoTheme.sleep)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Text(String(format: "%.1fh", vm.snapshot.sleepHours))
                                        .font(.title2.bold())
                                    Text("score \(vm.snapshot.sleepScore)/100")
                                        .font(.caption2)
                                        .foregroundStyle(RitmoTheme.textSecondary)
                                    FitProgressBar(
                                        value: vm.snapshot.sleepHours / 8.0,
                                        color: RitmoTheme.sleep
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Recupero (compact, beside Sonno)
                        if let recovery = vm.recovery {
                            Button { onNavigate?(3) } label: {
                                FitCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("Recupero", systemImage: "sparkles")
                                                .font(.caption).foregroundStyle(recoveryColor(recovery.status))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                        Text("\(recovery.overall)").font(.title2.bold())
                                        Text(LocalizedStringKey(recovery.status.label))
                                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                                        FitProgressBar(value: Double(recovery.overall) / 100,
                                                       color: recoveryColor(recovery.status))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Carico allenamento (compact, beside Salute)
                        if !sessions.isEmpty {
                            NavigationLink { TrainingLoadDetailView(sessions: sessions) } label: {
                                FitCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label("Carico", systemImage: "chart.bar.fill")
                                                .font(.caption).foregroundStyle(loadColor(trainingLoad.status))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                        Text("\(trainingLoad.acute)").font(.title2.bold())
                                        Text(LocalizedStringKey(trainingLoad.status.label))
                                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                                        FitProgressBar(value: min(trainingLoad.ratio / 1.5, 1),
                                                       color: loadColor(trainingLoad.status))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button { onNavigate?(4) } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label("Salute", systemImage: "heart.fill")
                                            .font(.caption).foregroundStyle(.red)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Text(vm.activity.heartRateResting.map { "\(Int($0)) bpm" } ?? "--")
                                        .font(.title2.bold())
                                    HStack(spacing: 4) {
                                        Text("HRV")
                                            .foregroundStyle(RitmoTheme.textSecondary)
                                        Text(vm.activity.hrv.map { "\(Int($0)) ms" } ?? "--")
                                            .foregroundStyle(.green)
                                    }
                                    .font(.caption2)
                                    HStack(spacing: 4) {
                                        Image(systemName: "drop.fill")
                                            .foregroundStyle(.cyan)
                                        Text(vm.activity.spO2.map { String(format: "%.0f%%", $0) } ?? "--")
                                            .foregroundStyle(.cyan)
                                        Text("SpO₂")
                                            .foregroundStyle(RitmoTheme.textSecondary)
                                    }
                                    .font(.caption2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: Riepilogo settimanale
                    if isToday, let recap = vm.weeklyRecap {
                        FitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    SectionHeader(title: "Settimana scorsa")
                                    Spacer()
                                    Text("\(recap.weekStart, format: .dateTime.day().month(.abbreviated)) – \(recap.lastDay, format: .dateTime.day().month(.abbreviated))")
                                        .font(.caption2)
                                        .foregroundStyle(RitmoTheme.textSecondary)
                                }
                                HStack(spacing: 0) {
                                    recapStat(value: "\(recap.workoutCount)",
                                              label: "allenamenti",
                                              delta: recap.workoutCount - recap.previousWorkoutCount == 0 ? nil
                                                  : Double(recap.workoutCount - recap.previousWorkoutCount),
                                              deltaIsPercent: false)
                                    recapStat(value: "\(Int(recap.totalLoad.rounded()))",
                                              label: "carico totale",
                                              delta: recap.loadDeltaPercent,
                                              deltaIsPercent: true)
                                    recapStat(value: recap.avgSleepHours > 0
                                                  ? String(format: "%.1fh", recap.avgSleepHours) : "--",
                                              label: "sonno medio",
                                              delta: nil, deltaIsPercent: false)
                                }
                                if let best = recap.bestSessionTitle {
                                    if let bestSession = sessions.first(where: { $0.id == recap.bestSessionID }) {
                                        NavigationLink {
                                            WorkoutDetailView(session: bestSession)
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "trophy.fill")
                                                    .font(.caption2).foregroundStyle(.yellow)
                                                Text("Allenamento top: ").font(.caption)
                                                    .foregroundStyle(RitmoTheme.textSecondary)
                                                + Text(LocalizedStringKey(best)).font(.caption.bold())
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        HStack(spacing: 5) {
                                            Image(systemName: "trophy.fill")
                                                .font(.caption2).foregroundStyle(.yellow)
                                            Text("Allenamento top: ").font(.caption)
                                                .foregroundStyle(RitmoTheme.textSecondary)
                                            + Text(LocalizedStringKey(best)).font(.caption.bold())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // MARK: Ultimo allenamento
                    if let session = vm.lastSession {
                        NavigationLink { WorkoutDetailView(session: session) } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        SectionHeader(title: "Ultimo allenamento")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(LocalizedStringKey(session.title))
                                                .font(.headline)
                                            Text(session.startTime, style: .relative)
                                                .font(.caption)
                                                .foregroundStyle(RitmoTheme.textSecondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(session.durationMinutes) min")
                                                .font(.subheadline.bold())
                                            Text("\(Int(session.totalVolumeKg / 1000))k kg vol.")
                                                .font(.caption)
                                                .foregroundStyle(RitmoTheme.textSecondary)
                                        }
                                    }
                                    if !session.muscleGroups.isEmpty {
                                        HStack {
                                            ForEach(session.muscleGroups, id: \.self) { group in
                                                Text(LocalizedStringKey(group.rawValue))
                                                    .font(.caption2)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(RitmoTheme.workout.opacity(0.15),
                                                                in: Capsule())
                                                    .foregroundStyle(RitmoTheme.workout)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: Insight top
                    if let topInsight = vm.topInsight {
                        Button { onNavigate?(5) } label: {
                            InsightBanner(insight: topInsight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle(isToday ? Text("Oggi") : Text(selectedDate, format: .dateTime.weekday(.wide).day().month().locale(locale)))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task { refresh() }
            .refreshable { refresh() }
        }
    }
}

// MARK: - DashboardView refresh helper
extension DashboardView {
    func refresh() {
        Task {
            await vm.refresh(for: selectedDate, healthRepo: healthRepo, modelContext: modelContext, goals: goals)
        }
    }
}
