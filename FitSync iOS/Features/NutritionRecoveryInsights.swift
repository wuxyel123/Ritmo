import SwiftUI
import SwiftData
import Charts
import FitSyncCore

// MARK: ── Shared period picker ─────────────────────────────────────────────

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week = "7G"
    case month = "30G"
    case year = "Anno"
    var id: String { rawValue }
    var days: Int {
        switch self { case .week: 7; case .month: 30; case .year: 365 }
    }
    var chartUnit: Calendar.Component {
        switch self { case .week: .day; case .month: .day; case .year: .month }
    }
}

// MARK: ── NUTRITION VIEW ───────────────────────────────────────────────────

struct NutritionView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query private var storedGoals: [UserGoals]
    @StateObject private var vm = NutritionViewModel()
    @State private var period: HistoryPeriod = .week
    @State private var selectedDate = Date.now

    var goals: UserGoals { storedGoals.first ?? UserGoals() }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Date navigation
                    DateNavigationBar(
                        selectedDate: $selectedDate,
                        isToday: isToday,
                        onDateChanged: { Task { await vm.loadDay(healthRepo: healthRepo, date: selectedDate) } },
                        healthRepo: healthRepo
                    )

                    // Today's macros
                    FitCard {
                        VStack(spacing: 12) {
                            HStack {
                                SectionHeader(title: isToday ? "Oggi" : selectedDate.formatted(.dateTime.day().month()))
                                Spacer()
                                if n.calories < 50 {
                                    Label("Dati via Yazio → Apple Health", systemImage: "info.circle")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            MacroRow(emoji: "🔥", label: "Calorie",
                                     current: n.calories, goal: goals.dailyCalories,
                                     unit: "kcal", color: FitSyncTheme.calories)
                            MacroRow(emoji: "🥩", label: "Proteine",
                                     current: n.protein, goal: goals.dailyProteinG,
                                     unit: "g", color: FitSyncTheme.protein)
                            MacroRow(emoji: "🍞", label: "Carboidrati",
                                     current: n.carbs, goal: goals.dailyCarbsG,
                                     unit: "g", color: FitSyncTheme.carbs)
                            MacroRow(emoji: "🥑", label: "Grassi",
                                     current: n.fat, goal: goals.dailyFatG,
                                     unit: "g", color: FitSyncTheme.fat)
                            MacroRow(emoji: "🌾", label: "Fibre",
                                     current: n.fiber, goal: goals.dailyFiberG,
                                     unit: "g", color: FitSyncTheme.fiber)
                            MacroRow(emoji: "💧", label: "Acqua",
                                     current: n.waterMl / 1000,
                                     goal: goals.dailyWaterMl / 1000,
                                     unit: "L", color: FitSyncTheme.water)
                        }
                    }

                    // Charts section
                    if !vm.history.isEmpty {
                        // Period picker
                        Picker("Periodo", selection: $period) {
                            ForEach(HistoryPeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: period) { _, p in
                            Task { await vm.loadHistory(healthRepo: healthRepo, days: p.days) }
                        }

                        macroChart("Calorie",   \.calories,         goals.dailyCalories,    "kcal", FitSyncTheme.calories, .bar)
                        macroChart("Proteine",  \.protein,          goals.dailyProteinG,    "g",    FitSyncTheme.protein,  .line)
                        macroChart("Carboidrati", \.carbs,          goals.dailyCarbsG,      "g",    FitSyncTheme.carbs,    .bar)
                        macroChart("Grassi",    \.fat,              goals.dailyFatG,         "g",    FitSyncTheme.fat,      .line)
                        macroChart("Fibre",     \.fiber,            goals.dailyFiberG,       "g",    FitSyncTheme.fiber,    .bar)
                        macroChart("Acqua",     { $0.waterMl/1000 }, goals.dailyWaterMl/1000,"L",    FitSyncTheme.water,    .bar)
                    }

                    // Yazio tip
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Come tracciare la nutrizione", systemImage: "lightbulb.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)
                            Text("FitSync legge automaticamente i dati nutrizionali da Apple Salute. Se usi **Yazio**, attiva la sincronizzazione in: Yazio → Profilo → Connessioni → Apple Salute. I dati appariranno qui automaticamente.")
                                .font(.caption)
                                .foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Nutrizione")
            .task {
                await vm.loadDay(healthRepo: healthRepo, date: selectedDate)
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
            .refreshable {
                await vm.loadDay(healthRepo: healthRepo, date: selectedDate)
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
        }
    }

    var n: NutritionDay { vm.selectedDay }

    @ViewBuilder
    func macroChart(_ title: String, _ value: @escaping (NutritionDay) -> Double,
                    _ goal: Double, _ unit: String, _ color: Color, _ type: ChartDisplayType) -> some View {
        let pts = vm.displayHistory.map { ChartPoint(date: $0.date, value: value($0)) }
        InteractiveDateChart(title: title, points: pts, goal: goal, color: color,
                             unit: unit, chartUnit: period.chartUnit, chartType: type)
    }
}

// MacroChartCard replaced by InteractiveDateChart (defined in FitSyncApp.swift)

@MainActor
final class NutritionViewModel: ObservableObject {
    @Published var selectedDay: NutritionDay = NutritionDay(date: .now)
    @Published var history: [NutritionDay] = []

    var displayHistory: [NutritionDay] {
        history.filter { $0.calories > 50 }.sorted { $0.date < $1.date }
    }

    func loadDay(healthRepo: HealthKitRepository, date: Date) async {
        selectedDay = await healthRepo.fetchNutrition(for: date)
    }

    func loadHistory(healthRepo: HealthKitRepository, days: Int) async {
        history = await healthRepo.fetchNutritionHistory(days: days)
    }
}

// MARK: ── RECOVERY VIEW ───────────────────────────────────────────────────

struct RecoveryView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query private var storedGoals: [UserGoals]
    @StateObject private var vm = RecoveryViewModel()
    @State private var period: HistoryPeriod = .week
    @State private var showingSleepDetail = false

    var goals: UserGoals { storedGoals.first ?? UserGoals() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // MARK: Sonno
                    if let sleep = vm.lastSleep {
                        Button { showingSleepDetail = true } label: {
                            FitCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Sonno stanotte").font(.headline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 0) {
                                        SleepMetric(value: String(format: "%.1fh", sleep.totalHours),
                                                    label: "totale", color: FitSyncTheme.sleep)
                                        SleepMetric(value: String(format: "%.1fh", sleep.deepSleepHours),
                                                    label: "profondo", color: .indigo)
                                        SleepMetric(value: String(format: "%.1fh", sleep.remSleepHours),
                                                    label: "REM", color: .purple)
                                        SleepMetric(value: "\(sleep.qualityScore)",
                                                    label: "score /100",
                                                    color: sleep.qualityScore > 70 ? .green : .orange)
                                    }
                                    FitProgressBar(value: sleep.totalHours / 8.0, color: FitSyncTheme.sleep)
                                    if !sleep.stages.isEmpty {
                                        SleepStageBar(session: sleep)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showingSleepDetail) {
                            SleepDetailSheet(session: sleep)
                        }
                    } else {
                        FitCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sonno stanotte").font(.headline)
                                EmptyDataView(
                                    message: "Nessun dato sonno. Assicurati che iPhone o Apple Watch registri il sonno. Puoi anche inserirlo manualmente in Apple Salute."
                                )
                            }
                        }
                    }

                    // MARK: Cuore & HRV (oggi)
                    FitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Cuore & HRV")
                            HStack(spacing: 0) {
                                HeartMetric(value: vm.activity.heartRateResting.map { "\(Int($0))" } ?? "--",
                                            label: "FC riposo", unit: "bpm", color: .red, icon: "heart.fill")
                                HeartMetric(value: vm.activity.heartRateAvg.map { "\(Int($0))" } ?? "--",
                                            label: "FC media", unit: "bpm", color: .pink, icon: "heart")
                                HeartMetric(value: vm.activity.hrv.map { "\(Int($0))" } ?? "--",
                                            label: "HRV", unit: "ms", color: .green, icon: "waveform.path.ecg",
                                            info: MetricInfo(
                                                title: "HRV — Variabilità Cardiaca",
                                                whatItIs: "La HRV (Heart Rate Variability) misura la variazione del tempo tra un battito cardiaco e il successivo. Valori alti indicano che il sistema nervoso autonomo è ben bilanciato: il corpo è pronto per lo sforzo fisico e il recupero è ottimale. Valori bassi segnalano stress, fatica o malattia.\n\nApple Watch la misura automaticamente durante il sonno.",
                                                goodValues: [
                                                    ("> 60 ms", "Eccellente — atletici o molto riposati", .green),
                                                    ("40–60 ms", "Buono — nella media degli adulti attivi", .blue),
                                                    ("20–40 ms", "Nella norma", .yellow),
                                                    ("< 20 ms", "Sotto la media — corpo sotto stress", .orange)
                                                ],
                                                tip: "La HRV varia molto da persona a persona. Monitora il TUO trend nel tempo: se la tua HRV è stabile o in aumento, stai recuperando bene. Un calo improvviso può indicare overtraining o malattia in arrivo."
                                            ))
                                HeartMetric(value: vm.activity.vo2Max.map { String(format: "%.0f", $0) } ?? "--",
                                            label: "VO₂ Max", unit: "ml/kg/min", color: .blue, icon: "lungs.fill",
                                            info: MetricInfo(
                                                title: "VO₂ Max",
                                                whatItIs: "Il VO₂ Max è la quantità massima di ossigeno che i tuoi muscoli riescono a utilizzare durante uno sforzo intenso. È il principale indicatore di fitness cardiovascolare e predice la salute a lungo termine.\n\nApple Watch lo stima durante camminate e corse all'aperto con GPS.",
                                                goodValues: [
                                                    ("> 55 ml/kg/min", "Eccellente (uomini) / > 48 (donne)", .green),
                                                    ("45–55", "Buono — sopra la media", .blue),
                                                    ("35–45", "Nella media", .yellow),
                                                    ("< 35", "Sotto la media — da migliorare", .orange)
                                                ],
                                                tip: "Il VO₂ Max migliora con l'allenamento aerobico regolare: corsa, ciclismo, nuoto. Anche 20-30 minuti di cardio moderato 3 volte a settimana producono benefici misurabili in poche settimane."
                                            ))
                            }
                        }
                    }

                    // MARK: Respiro & SpO2
                    FitCard {
                        HStack(spacing: 0) {
                            HeartMetric(value: vm.activity.spO2.map { String(format: "%.0f%%", $0) } ?? "--",
                                        label: "Ossigeno", unit: "SpO₂", color: .cyan, icon: "drop.fill",
                                        info: MetricInfo(
                                            title: "SpO₂ — Saturazione Ossigeno",
                                            whatItIs: "La SpO₂ misura la percentuale di emoglobina nel sangue che trasporta ossigeno. Un valore normale indica che i polmoni stanno ossigenando correttamente il sangue.\n\nApple Watch la misura con il sensore di ossigeno nel sangue sul retro. La misurazione avviene principalmente durante il sonno.",
                                            goodValues: [
                                                ("95–100%", "Normale — nessuna preoccupazione", .green),
                                                ("90–94%", "Lieve ipossia — monitora", .yellow),
                                                ("85–89%", "Ipossia moderata — consulta un medico", .orange),
                                                ("< 85%", "Ipossia grave — urgente", .red)
                                            ],
                                            tip: "Valori occasionalmente bassi durante il sonno possono indicare apnea notturna. Se la SpO₂ scende spesso sotto il 90% durante la notte, parla con il tuo medico."
                                        ))
                            HeartMetric(value: vm.activity.respiratoryRate.map { String(format: "%.0f", $0) } ?? "--",
                                        label: "Respiro", unit: "atti/min", color: .teal, icon: "wind",
                                        info: MetricInfo(
                                            title: "Frequenza Respiratoria",
                                            whatItIs: "La frequenza respiratoria è il numero di atti respiratori (inspirazione + espirazione) al minuto durante il riposo. È un indicatore sensibile dello stato di salute: si alza in caso di stress, malattia o recupero insufficiente.\n\nApple Watch la misura durante il sonno tramite l'accelerometro.",
                                            goodValues: [
                                                ("12–16 atti/min", "Ottimale a riposo", .green),
                                                ("16–20 atti/min", "Normale", .blue),
                                                ("20–25 atti/min", "Elevata — possibile stress", .yellow),
                                                ("> 25 atti/min", "Alta — consulta un medico", .orange)
                                            ],
                                            tip: "Un aumento della frequenza respiratoria notturna rispetto al tuo solito può essere uno dei primi segnali di un'infezione in arrivo, anche prima che compaiano altri sintomi."
                                        ))
                            HeartMetric(value: "\(vm.activity.flightsClimbed)",
                                        label: "Scale", unit: "piani", color: .orange, icon: "figure.stairs")
                            HeartMetric(value: "\(vm.activity.mindfulMinutes)",
                                        label: "Mindfulness", unit: "min", color: .purple, icon: "brain")
                        }
                    }

                    // MARK: Periodo
                    Picker("Periodo", selection: $period) {
                        ForEach(HistoryPeriod.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, p in
                        Task { await vm.loadHistory(healthRepo: healthRepo, days: p.days) }
                    }

                    // MARK: Grafico ore sonno
                    if !vm.sleepHistory.isEmpty {
                        FitCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Ore di sonno")
                                Chart(vm.sleepHistory) { s in
                                    BarMark(x: .value("Notte", s.startTime, unit: .day),
                                            y: .value("Ore", s.totalHours),
                                            width: .fixed(12))
                                        .foregroundStyle(s.totalHours >= 7 ? FitSyncTheme.sleep : .orange)
                                        .cornerRadius(4)
                                    RuleMark(y: .value("Obiettivo", 8))
                                        .foregroundStyle(FitSyncTheme.sleep.opacity(0.5))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                        .annotation(position: .trailing, alignment: .center) {
                                            Text("8h").font(.system(size: 8)).foregroundStyle(FitSyncTheme.sleep)
                                        }
                                }
                                .frame(height: 110)
                                .chartYScale(domain: 0...12)
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day)) {
                                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                                    }
                                }
                            }
                        }
                    }

                    // MARK: Grafico HRV
                    if !vm.hrvHistory.isEmpty {
                        let hrvVals = vm.hrvHistory.map(\.value)
                        let hrvLo = max(0, (hrvVals.min() ?? 0) - 5)
                        let hrvHi = (hrvVals.max() ?? 100) + 5
                        InteractiveDateChart(
                            title: "HRV — Heart Rate Variability",
                            points: vm.hrvHistory.map { ChartPoint(date: $0.date, value: $0.value) },
                            goal: nil, color: .green, unit: "ms", chartUnit: .day, chartType: .line,
                            yDomain: hrvLo...hrvHi
                        )
                    }

                    // MARK: Grafico FC Riposo
                    if !vm.rhrHistory.isEmpty {
                        let rhrVals = vm.rhrHistory.map(\.value)
                        let rhrLo = max(0, (rhrVals.min() ?? 40) - 5)
                        let rhrHi = (rhrVals.max() ?? 80) + 5
                        InteractiveDateChart(
                            title: "FC a riposo",
                            points: vm.rhrHistory.map { ChartPoint(date: $0.date, value: $0.value) },
                            goal: nil, color: .red, unit: "bpm", chartUnit: .day, chartType: .line,
                            yDomain: rhrLo...rhrHi
                        )
                    }

                    // MARK: Peso corporeo
                    if !vm.weightHistory.isEmpty {
                        let wVals = vm.weightHistory.map(\.value)
                        let wLo = max(0, (wVals.min() ?? 50) - 2)
                        let wHi = (wVals.max() ?? 100) + 2
                        InteractiveDateChart(
                            title: "Peso corporeo",
                            points: vm.weightHistory.map { ChartPoint(date: $0.date, value: $0.value) },
                            goal: nil, color: .primary, unit: "kg", chartUnit: .day, chartType: .line,
                            yDomain: wLo...wHi
                        )
                    }

                    // MARK: Corpo
                    if let metric = vm.bodyMetric {
                        FitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Composizione corporea")
                                HStack(spacing: 0) {
                                    HeartMetric(value: metric.weightKg.map { String(format: "%.1f", $0) } ?? "--",
                                                label: "Peso", unit: "kg", color: .primary, icon: "scalemass.fill")
                                    HeartMetric(value: metric.bodyFatPercentage.map { String(format: "%.1f", $0) } ?? "--",
                                                label: "Grasso corp.", unit: "%", color: .orange, icon: "chart.pie.fill")
                                    HeartMetric(value: metric.bmi.map { String(format: "%.1f", $0) } ?? "--",
                                                label: "BMI", unit: "", color: .blue, icon: "person.fill")
                                    HeartMetric(value: metric.leanBodyMassKg.map { String(format: "%.1f", $0) } ?? "--",
                                                label: "Massa magra", unit: "kg", color: .green, icon: "figure.strengthtraining.traditional")
                                }
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Recupero")
            .task {
                async let a = healthRepo.fetchDailyActivity(for: .now)
                async let b = healthRepo.fetchLatestBodyMetric()
                vm.activity = await a
                vm.bodyMetric = await b
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
            .refreshable {
                vm.activity = await healthRepo.fetchDailyActivity(for: .now)
                vm.bodyMetric = await healthRepo.fetchLatestBodyMetric()
                await vm.loadHistory(healthRepo: healthRepo, days: period.days)
            }
        }
    }
}

// MARK: ── Recovery sub-views ──────────────────────────────────────────────

struct SleepMetric: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(FitSyncTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SleepStageBar: View {
    let session: SleepSession
    var deepH: Double { session.deepSleepHours }
    var remH: Double { session.remSleepHours }
    var coreH: Double { session.stages.filter { $0.type == .core }.reduce(0) { $0 + $1.durationHours } }
    var total: Double { max(session.totalHours, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(deepH / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.purple)
                        .frame(width: geo.size.width * CGFloat(remH / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(FitSyncTheme.sleep)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                legend(.indigo, "Profondo")
                legend(.purple, "REM")
                legend(FitSyncTheme.sleep, "Core")
            }
            .font(.caption2)
        }
        .padding(.top, 4)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(FitSyncTheme.textSecondary)
        }
    }
}

// TrendChartCard replaced by InteractiveDateChart (defined in FitSyncApp.swift)

struct MetricInfo {
    let title: String
    let whatItIs: String
    let goodValues: [(range: String, label: String, color: Color)]
    let tip: String
}

struct HeartMetric: View {
    let value: String; let label: String; let unit: String
    let color: Color; let icon: String
    var info: MetricInfo? = nil

    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                    .frame(maxWidth: .infinity)
                if info != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            Text(value).font(.title3.bold())
            Text(unit).font(.system(size: 9)).foregroundStyle(FitSyncTheme.textSecondary)
            Text(label).font(.system(size: 9)).foregroundStyle(FitSyncTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if info != nil { showingInfo = true } }
        .sheet(isPresented: $showingInfo) {
            if let info { MetricInfoSheet(info: info) }
        }
    }
}

struct MetricInfoSheet: View {
    let info: MetricInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // What it is
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cos'è", systemImage: "questionmark.circle")
                            .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                        Text(info.whatItIs)
                            .font(.body).foregroundStyle(.primary)
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    // Good values
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Valori di riferimento", systemImage: "chart.bar")
                            .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                        ForEach(info.goodValues, id: \.range) { entry in
                            HStack(spacing: 12) {
                                Circle().fill(entry.color).frame(width: 10, height: 10)
                                Text(entry.range).font(.subheadline.bold()).frame(width: 90, alignment: .leading)
                                Text(entry.label).font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
                            }
                        }
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    // Tip
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Consiglio", systemImage: "lightbulb")
                            .font(.subheadline.bold()).foregroundStyle(.yellow)
                        Text(info.tip)
                            .font(.body).foregroundStyle(.primary)
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle(info.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct EmptyDataView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding()
    }
}

struct SleepDetailSheet: View {
    let session: SleepSession
    @Environment(\.dismiss) private var dismiss

    var coreHours: Double {
        session.stages.filter { $0.type == .core }.reduce(0) { $0 + $1.durationHours }
    }
    var awakeHours: Double {
        session.stages.filter { $0.type == .awake }.reduce(0) { $0 + $1.durationHours }
    }
    var qualityColor: Color {
        session.qualityScore >= 75 ? .green : session.qualityScore >= 50 ? .orange : .red
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // Score ring + key times
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(session.qualityScore) / 100)
                                .stroke(qualityColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(session.qualityScore)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(qualityColor)
                                Text("/ 100")
                                    .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                            }
                        }
                        .frame(width: 90, height: 90)

                        VStack(alignment: .leading, spacing: 8) {
                            sleepTimeRow("Addormentamento", session.startTime, "moon.zzz.fill", .indigo)
                            sleepTimeRow("Sveglia", session.endTime, "sun.horizon.fill", .orange)
                            HStack(spacing: 6) {
                                Image(systemName: "clock").foregroundStyle(FitSyncTheme.sleep).font(.caption)
                                Text(String(format: "%.1f ore totali", session.totalHours))
                                    .font(.subheadline.bold())
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))

                    // Stage breakdown numbers
                    FitCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fasi del sonno").font(.headline)
                            HStack(spacing: 0) {
                                stageMetric(String(format: "%.1fh", session.deepSleepHours),
                                            "Profondo", .indigo, "Restaurativo")
                                stageMetric(String(format: "%.1fh", session.remSleepHours),
                                            "REM", .purple, "Sogni / memoria")
                                stageMetric(String(format: "%.1fh", coreHours),
                                            "Core", FitSyncTheme.sleep, "Sonno leggero")
                                if awakeHours > 0 {
                                    stageMetric(String(format: "%.1fh", awakeHours),
                                                "Sveglio", .orange, "Svegliate")
                                }
                            }
                            if !session.stages.isEmpty {
                                SleepStageBar(session: session)
                            }
                        }
                    }

                    // Stage timeline
                    if !session.stages.isEmpty {
                        FitCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Timeline").font(.headline)
                                ForEach(session.stages.sorted { $0.startTime < $1.startTime }) { stage in
                                    HStack(spacing: 10) {
                                        Circle().fill(stageColor(stage.type)).frame(width: 8, height: 8)
                                        Text(stage.startTime, format: .dateTime.hour().minute())
                                            .font(.caption).frame(width: 44, alignment: .leading)
                                        Text(stage.type.rawValue).font(.caption.bold())
                                        Spacer()
                                        Text(String(format: "%.0f min", stage.durationHours * 60))
                                            .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    // Score explanation
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Come si calcola il punteggio", systemImage: "info.circle")
                                .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                            scoreRow("Durata (max 50 pt)",
                                     Int(min(session.totalHours / 8.0, 1.0) * 50),
                                     "Obiettivo: 8 ore di sonno")
                            scoreRow("Sonno profondo (max 30 pt)",
                                     Int(min(session.deepSleepHours / 1.5, 1.0) * 30),
                                     "Obiettivo: 1.5 ore di sonno profondo")
                            scoreRow("Sonno REM (max 20 pt)",
                                     Int(min(session.remSleepHours / 1.5, 1.0) * 20),
                                     "Obiettivo: 1.5 ore di REM")
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Dettaglio sonno")
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

    private func stageColor(_ type: SleepStageType) -> Color {
        switch type {
        case .deep: return .indigo
        case .rem: return .purple
        case .core: return FitSyncTheme.sleep
        case .awake: return .orange
        case .unspecified: return .gray
        }
    }

    @ViewBuilder
    private func sleepTimeRow(_ label: String, _ date: Date, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                Text(date, format: .dateTime.hour().minute()).font(.subheadline.bold())
            }
        }
    }

    @ViewBuilder
    private func stageMetric(_ value: String, _ label: String, _ color: Color, _ sub: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2.bold())
            Text(sub).font(.system(size: 8)).foregroundStyle(FitSyncTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func scoreRow(_ label: String, _ pts: Int, _ description: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.bold())
                Text(description).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
            }
            Spacer()
            Text("\(pts) pt").font(.caption.bold()).foregroundStyle(FitSyncTheme.accent)
        }
    }
}

@MainActor
final class RecoveryViewModel: ObservableObject {
    @Published var lastSleep: SleepSession?
    @Published var sleepHistory: [SleepSession] = []
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var bodyMetric: BodyMetric?
    @Published var hrvHistory: [DateValuePoint] = []
    @Published var rhrHistory: [DateValuePoint] = []
    @Published var weightHistory: [DateValuePoint] = []

    func loadHistory(healthRepo: HealthKitRepository, days: Int) async {
        // Sleep history for charts (day-by-day, limited to period)
        let chartDays = min(days, 30)
        var sleepArr: [SleepSession] = []
        for i in 0..<chartDays {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: .now),
               let s = await healthRepo.fetchSleep(for: d) {
                sleepArr.append(s)
            }
        }
        sleepHistory = sleepArr

        async let todaySleep = healthRepo.fetchSleep(for: .now)
        async let hrv = healthRepo.fetchHRVHistory(days: days)
        async let rhr = healthRepo.fetchRHRHistory(days: days)
        async let wt  = healthRepo.fetchBodyWeightHistoryPoints(days: days)
        lastSleep  = await todaySleep
        hrvHistory = await hrv
        rhrHistory = await rhr
        weightHistory = await wt
    }
}

// MARK: ── INSIGHTS VIEW ───────────────────────────────────────────────────

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
                VStack(spacing: FitSyncTheme.gap) {

                    // How-it-works info banner
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Come funzionano gli Insights", systemImage: "brain.head.profile")
                                .font(.subheadline.bold()).foregroundStyle(FitSyncTheme.accent)
                            Text("Gli insights analizzano automaticamente: bilancio muscolare (push/pull/gambe), variabilità del sonno, distribuzione delle proteine nei giorni di allenamento vs riposo, e correlazioni tra recupero e performance. Più dati hai (almeno 2 settimane), più sono accurati.")
                                .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                        }
                    }

                    if vm.isLoading {
                        ProgressView("Analizzando i tuoi dati…")
                            .padding(.vertical, 40)
                    } else if vm.insights.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 60)).foregroundStyle(FitSyncTheme.accent.opacity(0.4))
                            Text("Nessun insight disponibile")
                                .font(.title3.bold())
                            Text("Importa almeno 2 settimane di allenamenti da Hevy e attiva la sincronizzazione di Yazio con Apple Salute per ricevere insights personalizzati.")
                                .font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }.padding(FitSyncTheme.pagePadding)
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
                                                    .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(String(format: "%.1f kg × %d", pr.weightKg, pr.reps))
                                                    .font(.subheadline.bold())
                                                Text(String(format: "~%.0f kg 1RM", pr.estimatedOneRepMax))
                                                    .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
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
                                            .foregroundStyle(FitSyncTheme.workout)
                                            .cornerRadius(4)
                                    }
                                    .frame(height: CGFloat(vm.muscleVolume.count) * 28)
                                    .chartXAxisLabel("Volume (×1000 kg)")
                                }
                            }
                        }
                    }
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Insights")
            .task { await vm.load(healthRepo: healthRepo, sessions: sessions, goals: goals) }
        }
    }
}

struct InsightCard: View {
    let insight: FitInsight
    var accentColor: Color {
        switch insight.type {
        case .warning: .orange; case .suggestion: .blue
        case .tip: .purple; case .positive: .green
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(insight.icon).font(.title3)
                Text(insight.title).font(.subheadline.bold()).foregroundStyle(accentColor)
                Spacer()
                Text(insight.category.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(accentColor)
            }
            Text(insight.message).font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
        }
        .padding(FitSyncTheme.cardPadding)
        .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius)
            .stroke(accentColor.opacity(0.3), lineWidth: 1))
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

// GoalsSettingsView removed — use the Obiettivi tab in Settings for macro goals.
