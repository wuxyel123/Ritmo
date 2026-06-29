import SwiftUI
import SwiftData
import Charts
import FitSyncCore

struct DashboardView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var storedGoals: [UserGoals]
    @StateObject private var vm = DashboardViewModel()
    @State private var selectedDate = Date.now
    @State private var showingCaloriesDetail = false
    @State private var showingStepsDetail = false
    var onNavigate: ((Int) -> Void)? = nil

    var goals: UserGoals { storedGoals.first ?? UserGoals() }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // MARK: Navigazione date
                    DateNavigationBar(
                        selectedDate: $selectedDate,
                        isToday: isToday,
                        onDateChanged: { refresh() },
                        healthRepo: healthRepo
                    )

                    // MARK: Score del giorno
                    DayScoreCard(snapshot: vm.snapshot)

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
                                         unit: "kcal", color: FitSyncTheme.calories)
                                MacroRow(emoji: "🥩", label: "Proteine",
                                         current: vm.snapshot.protein, goal: vm.snapshot.proteinGoal,
                                         unit: "g", color: FitSyncTheme.protein)
                                MacroRow(emoji: "🍞", label: "Carboidrati",
                                         current: vm.snapshot.carbs, goal: vm.snapshot.carbsGoal,
                                         unit: "g", color: FitSyncTheme.carbs)
                                MacroRow(emoji: "🥑", label: "Grassi",
                                         current: vm.snapshot.fat, goal: vm.snapshot.fatGoal,
                                         unit: "g", color: FitSyncTheme.fat)
                                MacroRow(emoji: "💧", label: "Acqua",
                                         current: vm.snapshot.waterMl / 1000, goal: vm.snapshot.waterGoal / 1000,
                                         unit: "L", color: FitSyncTheme.water,
                                         fractionDigits: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: Attività (Move / Steps / Sleep)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: FitSyncTheme.gap) {
                        Button { showingCaloriesDetail = true } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Calorie attive", systemImage: "bolt.fill")
                                        .font(.caption).foregroundStyle(.red)
                                    Text("\(Int(vm.snapshot.activeCalories))")
                                        .font(.title2.bold())
                                    Text("su \(Int(vm.snapshot.activeCalorieGoal)) kcal")
                                        .font(.caption2)
                                        .foregroundStyle(FitSyncTheme.textSecondary)
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
                                    Label("Passi", systemImage: "figure.walk")
                                        .font(.caption).foregroundStyle(FitSyncTheme.steps)
                                    Text(vm.snapshot.steps.formatted())
                                        .font(.title2.bold())
                                    Text("su \(vm.snapshot.stepGoal.formatted())")
                                        .font(.caption2)
                                        .foregroundStyle(FitSyncTheme.textSecondary)
                                    FitProgressBar(
                                        value: Double(vm.snapshot.steps) / Double(max(vm.snapshot.stepGoal, 1)),
                                        color: FitSyncTheme.steps
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
                                    Label("Sonno", systemImage: "bed.double.fill")
                                        .font(.caption).foregroundStyle(FitSyncTheme.sleep)
                                    Text(String(format: "%.1fh", vm.snapshot.sleepHours))
                                        .font(.title2.bold())
                                    Text("score \(vm.snapshot.sleepScore)/100")
                                        .font(.caption2)
                                        .foregroundStyle(FitSyncTheme.textSecondary)
                                    FitProgressBar(
                                        value: vm.snapshot.sleepHours / 8.0,
                                        color: FitSyncTheme.sleep
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: Ultimo allenamento
                    if let session = vm.lastSession {
                        Button { vm.showingLastWorkoutDetail = true } label: {
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
                                                .foregroundStyle(FitSyncTheme.textSecondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(session.durationMinutes) min")
                                                .font(.subheadline.bold())
                                            Text("\(Int(session.totalVolumeKg / 1000))k kg vol.")
                                                .font(.caption)
                                                .foregroundStyle(FitSyncTheme.textSecondary)
                                        }
                                    }
                                    if !session.muscleGroups.isEmpty {
                                        HStack {
                                            ForEach(session.muscleGroups, id: \.self) { group in
                                                Text(LocalizedStringKey(group.rawValue))
                                                    .font(.caption2)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(FitSyncTheme.workout.opacity(0.15),
                                                                in: Capsule())
                                                    .foregroundStyle(FitSyncTheme.workout)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $vm.showingLastWorkoutDetail) {
                            NavigationStack {
                                WorkoutDetailView(session: session)
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) {
                                            Button("Chiudi") { vm.showingLastWorkoutDetail = false }
                                        }
                                    }
                            }
                        }
                    }

                    // MARK: Insight top
                    if let topInsight = vm.topInsight {
                        InsightBanner(insight: topInsight)
                    }
                }
                .padding(FitSyncTheme.pagePadding)
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

// MARK: - Date Navigation Bar (tap date → calendar picker with data dots)

struct DateNavigationBar: View {
    @Binding var selectedDate: Date
    let isToday: Bool
    let onDateChanged: () -> Void
    var healthRepo: HealthKitRepository? = nil

    @Environment(\.locale) private var locale
    private let calendar = Calendar.current
    @State private var showingCalendar = false
    @State private var daysWithData: Set<String> = []

    var body: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate)!
                onDateChanged()
            } label: {
                Image(systemName: "chevron.left").font(.headline).padding(8)
            }

            Spacer()

            Button { showingCalendar = true } label: {
                VStack(spacing: 2) {
                    if isToday {
                        Text("Oggi").font(.headline.bold())
                    } else {
                        Text(selectedDate, format: .dateTime.weekday(.wide).locale(locale)).font(.headline.bold())
                        Text(selectedDate, format: .dateTime.day().month().year().locale(locale))
                            .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                    }
                    Image(systemName: "calendar").font(.caption2).foregroundStyle(FitSyncTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingCalendar) {
                NavigationStack {
                    FitCalendarView(selectedDate: $selectedDate, daysWithData: daysWithData) {
                        showingCalendar = false; onDateChanged()
                    }
                    .navigationTitle("Scegli giorno")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showingCalendar = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: showingCalendar) {
                guard showingCalendar, let repo = healthRepo else { return }
                daysWithData = await repo.fetchDaysWithActivity(in: selectedDate)
            }

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate)!
                onDateChanged()
            } label: {
                Image(systemName: "chevron.right").font(.headline).padding(8)
            }
            .disabled(isToday).opacity(isToday ? 0.3 : 1)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Day Score Card
struct DayScoreCard: View {
    let snapshot: DailySnapshot
    @State private var showingDetail = false

    var scoreColor: Color {
        switch snapshot.dayScore {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        Button { showingDetail = true } label: {
            FitCard {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.dayScore) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(snapshot.dayScore)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }
                    .frame(width: 90, height: 90)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Score del giorno")
                            .font(.headline)
                        Text(scoreLabel(snapshot.dayScore))
                            .font(.subheadline)
                            .foregroundStyle(scoreColor)
                        Text(snapshot.hasWorkedOutToday ? "💪 Allenamento completato" : "🛋️ Giorno di riposo")
                            .font(.caption)
                            .foregroundStyle(FitSyncTheme.textSecondary)
                        Text(snapshot.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(FitSyncTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            DayScoreDetailSheet(snapshot: snapshot)
        }
    }

    private func scoreLabel(_ score: Int) -> LocalizedStringKey {
        switch score {
        case 90...: return "Giornata perfetta! 🌟"
        case 75..<90: return "Ottima giornata"
        case 60..<75: return "Buona giornata"
        case 40..<60: return "Giornata nella media"
        default: return "Puoi fare meglio"
        }
    }
}

// MARK: - Day Score Detail Sheet
struct DayScoreDetailSheet: View {
    let snapshot: DailySnapshot
    @Environment(\.dismiss) private var dismiss

    var scoreColor: Color {
        switch snapshot.dayScore {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Big ring summary
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.15), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.dayScore) / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(snapshot.dayScore)")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(scoreColor)
                            Text("su 100")
                                .font(.subheadline)
                                .foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    .padding(.top, 8)

                    // Score components
                    FitCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Componenti del punteggio")
                                .font(.headline)

                            ScoreComponentRow(
                                icon: "figure.walk", label: "Movimento",
                                description: "Passi (\(snapshot.steps.formatted())) + calorie attive (\(Int(snapshot.activeCalories)) kcal)",
                                score: snapshot.movementScore, maxScore: 40, color: .orange
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "bed.double.fill", label: "Recupero",
                                description: snapshot.sleepHours > 0
                                    ? "Sonno \(String(format: "%.1f", snapshot.sleepHours))h · qualità \(snapshot.sleepScore)/100"
                                    : "Nessun dato sonno — punteggio neutro",
                                score: snapshot.recoveryScore, maxScore: 30, color: FitSyncTheme.sleep
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "fork.knife", label: "Nutrizione",
                                description: snapshot.calories > 50
                                    ? "Calorie \(Int(snapshot.calories))/\(Int(snapshot.calorieGoal)) · Proteine \(Int(snapshot.protein))/\(Int(snapshot.proteinGoal))g"
                                    : "Nessun dato nutrizionale — punteggio neutro",
                                score: snapshot.nutritionScore, maxScore: 20, color: FitSyncTheme.calories
                            )
                            Divider()
                            ScoreComponentRow(
                                icon: "dumbbell.fill", label: "Allenamento",
                                description: snapshot.hasWorkedOutToday
                                    ? "Allenamento completato oggi"
                                    : snapshot.workoutBonus >= 10
                                        ? "Passi raggiunti — riposo attivo"
                                        : "Nessun allenamento oggi",
                                score: snapshot.workoutBonus, maxScore: 10, color: FitSyncTheme.workout
                            )
                        }
                    }

                    // How it's calculated explanation
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Come si calcola", systemImage: "info.circle")
                                .font(.subheadline.bold())
                                .foregroundStyle(FitSyncTheme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                explanationRow("Movimento (max 40 pt)", "Media pesata di passi e calorie attive rispetto agli obiettivi. Richiede solo iPhone o Apple Watch.")
                                explanationRow("Recupero (max 30 pt)", "Basato sulla qualità del sonno. Se mancano i dati sonno viene assegnato un punteggio neutro di 15 pt.")
                                explanationRow("Nutrizione (max 20 pt)", "Progressione verso obiettivo calorie (40%) e proteine (60%). Se non tracciata → 10 pt neutri.")
                                explanationRow("Allenamento (max 10 pt)", "Pieno punteggio con un allenamento, o se raggiungi l'obiettivo passi (riposo attivo intenzionale). Parziale in proporzione ai passi se nessuno dei due.")
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Score del giorno")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func explanationRow(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(body).font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
        }
    }
}

struct ScoreComponentRow: View {
    let icon: String
    let label: LocalizedStringKey
    let description: String
    let score: Double
    let maxScore: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(score)) / \(Int(maxScore)) pt")
                        .font(.subheadline.bold())
                        .foregroundStyle(color)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                FitProgressBar(value: score / maxScore, color: color, height: 5)
            }
        }
    }
}

// MARK: - Insight Banner
struct InsightBanner: View {
    let insight: FitInsight

    var bgColor: Color {
        switch insight.type {
        case .warning: return .orange.opacity(0.12)
        case .suggestion: return .blue.opacity(0.12)
        case .tip: return .purple.opacity(0.12)
        case .positive: return .green.opacity(0.12)
        }
    }

    var accentColor: Color {
        switch insight.type {
        case .warning: return .orange
        case .suggestion: return .blue
        case .tip: return .purple
        case .positive: return .green
        }
    }

    private var localizedMessage: String {
        let format = NSLocalizedString(insight.messageKey, comment: "")
        guard !insight.messageArgs.isEmpty else { return format }
        let args: [CVarArg] = insight.messageArgs.map { $0 as CVarArg }
        return String(format: format, arguments: args)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(insight.icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(insight.title))
                    .font(.subheadline.bold())
                    .foregroundStyle(accentColor)
                Text(localizedMessage)
                    .font(.caption)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(FitSyncTheme.cardPadding)
        .background(bgColor, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
    }
}

// MARK: - Activity Metric Detail (Active Calories / Steps)

enum ActivityMetricKind {
    case activeCalories, steps

    var title: String   { self == .activeCalories ? "Calorie attive" : "Passi" }
    var unit: String    { self == .activeCalories ? "kcal" : "" }
    var icon: String    { self == .activeCalories ? "bolt.fill" : "figure.walk" }
    var color: Color    { self == .activeCalories ? .red : FitSyncTheme.steps }
    var chartType: ChartDisplayType { .bar }
}

struct ActivityMetricDetailView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query private var storedGoals: [UserGoals]
    @Environment(\.dismiss) private var dismiss

    let metric: ActivityMetricKind

    @State private var period: HistoryPeriod = .week
    @State private var history: [DateValuePoint] = []
    @State private var isLoading = true

    var goal: Double {
        let g = storedGoals.first ?? UserGoals()
        return metric == .activeCalories ? g.dailyActiveCalories : Double(g.dailySteps)
    }

    var points: [ChartPoint] { history.map { ChartPoint(date: $0.date, value: $0.value) } }

    var avg: Double {
        guard !history.isEmpty else { return 0 }
        return history.map(\.value).reduce(0, +) / Double(history.count)
    }
    var maxVal: Double { history.map(\.value).max() ?? 0 }
    var daysOnGoal: Int { history.filter { $0.value >= goal }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Stats strip
                    HStack(spacing: 0) {
                        statPill(label: "Media", value: formatted(avg), color: metric.color)
                        Divider().frame(height: 40)
                        statPill(label: "Massimo", value: formatted(maxVal), color: .primary)
                        Divider().frame(height: 40)
                        statPill(label: "Giorni obiettivo", value: "\(daysOnGoal)/\(history.count)", color: goal > 0 ? .green : .secondary)
                    }
                    .padding(.vertical, 6)
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    // Period picker
                    Picker("Periodo", selection: $period) {
                        ForEach(HistoryPeriod.allCases) { p in Text(p.localizedLabel).tag(p) }
                    }
                    .pickerStyle(.segmented)

                    if isLoading {
                        ProgressView().frame(height: 180)
                    } else if history.isEmpty {
                        Text("Nessun dato per questo periodo")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding()
                    } else {
                        // Main chart
                        InteractiveDateChart(
                            title: metric.title,
                            points: points,
                            goal: goal > 0 ? goal : nil,
                            color: metric.color,
                            unit: metric.unit,
                            chartUnit: period.chartUnit,
                            chartType: metric.chartType
                        )

                        // Per-day breakdown (last 10 entries)
                        FitCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Giorni recenti")
                                ForEach(history.sorted { $0.date > $1.date }.prefix(10), id: \.date) { pt in
                                    HStack {
                                        Text(pt.date, format: .dateTime.weekday(.wide).day().month())
                                            .font(.subheadline).foregroundStyle(.primary)
                                        Spacer()
                                        Text(formatted(pt.value))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(pt.value >= goal ? .green : metric.color)
                                        if goal > 0 {
                                            Image(systemName: pt.value >= goal ? "checkmark.circle.fill" : "circle")
                                                .font(.caption).foregroundStyle(pt.value >= goal ? .green : .secondary)
                                        }
                                    }
                                    if pt.date != history.sorted { $0.date > $1.date }.prefix(10).last?.date {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle(LocalizedStringKey(metric.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .task(id: period) {
                isLoading = true
                await loadHistory()
                isLoading = false
            }
        }
    }

    private func loadHistory() async {
        switch metric {
        case .activeCalories:
            history = await healthRepo.fetchActiveCaloriesHistory(days: period.days)
        case .steps:
            history = await healthRepo.fetchStepsHistory(days: period.days)
        }
    }

    private func formatted(_ v: Double) -> String {
        if metric == .steps {
            return Int(v).formatted()
        }
        return "\(Int(v)) kcal"
    }

    @ViewBuilder
    private func statPill(label: LocalizedStringKey, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
