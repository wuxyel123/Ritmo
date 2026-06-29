import SwiftUI
import SwiftData
import Charts
import FitSyncCore

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
                                        label: "Salite", unit: "piani", color: .orange, icon: "figure.stairs")
                            HeartMetric(value: "\(vm.activity.mindfulMinutes)",
                                        label: "Mindfulness", unit: "min", color: .purple, icon: "brain")
                        }
                    }

                    // MARK: Periodo
                    Picker("Periodo", selection: $period) {
                        ForEach(HistoryPeriod.allCases) { p in
                            Text(p.localizedLabel).tag(p)
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
