import SwiftUI
import Charts
import RitmoCore

struct HealthView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @StateObject private var vm = HealthViewModel()
    @State private var period: HistoryPeriod = .week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RitmoTheme.gap) {

                    // MARK: Peso — tendenza
                    WeightTrendCard()

                    // MARK: Cuore & HRV
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

                    // MARK: Respiro & SpO₂
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

                    // MARK: Body composition
                    if let metric = vm.bodyMetric {
                        FitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Composizione corporea")
                                HStack(spacing: 0) {
                                    HeartMetric(value: metric.weightKg.map { String(format: "%.2f", $0) } ?? "--",
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

                    // MARK: Period picker
                    Picker("Periodo", selection: $period) {
                        ForEach(HistoryPeriod.allCases) { p in
                            Text(p.localizedLabel).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, p in
                        Task { await vm.loadHistory(healthRepo: healthRepo, days: p.days) }
                    }

                    // MARK: HRV chart
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

                    // MARK: RHR chart
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

                    // MARK: Weight chart
                    if !vm.weightHistory.isEmpty {
                        let wVals = vm.weightHistory.map(\.value)
                        let wLo = max(0, (wVals.min() ?? 50) - 2)
                        let wHi = (wVals.max() ?? 100) + 2
                        InteractiveDateChart(
                            title: "Peso corporeo",
                            points: vm.weightHistory.map { ChartPoint(date: $0.date, value: $0.value) },
                            goal: nil, color: .primary, unit: "kg", chartUnit: .day, chartType: .line,
                            yDomain: wLo...wHi, decimals: 2
                        )
                    }
                }
                .padding(RitmoTheme.pagePadding)
            }
            .navigationTitle("Salute")
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

// MARK: - ViewModel

@MainActor
final class HealthViewModel: ObservableObject {
    @Published var activity: DailyActivity = DailyActivity(date: .now)
    @Published var bodyMetric: BodyMetric?
    @Published var hrvHistory: [DateValuePoint] = []
    @Published var rhrHistory: [DateValuePoint] = []
    @Published var weightHistory: [DateValuePoint] = []

    func loadHistory(healthRepo: HealthKitRepository, days: Int) async {
        async let hrv = healthRepo.fetchHRVHistory(days: days)
        async let rhr = healthRepo.fetchRHRHistory(days: days)
        async let wt  = healthRepo.fetchBodyWeightHistoryPoints(days: days)
        hrvHistory    = await hrv
        rhrHistory    = await rhr
        weightHistory = await wt
    }
}

// MARK: - WeightTrendCard (7-day smoothed + kg/week rate)

struct WeightTrendCard: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @State private var average7: Double?
    @State private var ratePerWeek: Double?

    var body: some View {
        Group {
            if let average7 {
                FitCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Peso — tendenza")
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.2f", average7))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(RitmoTheme.accent)
                            Text("kg · media 7 giorni").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let ratePerWeek {
                                Text(String(format: "%+.2f kg/sett.", ratePerWeek))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(abs(ratePerWeek) < 0.05 ? Color.secondary
                                                     : (ratePerWeek > 0 ? Color.orange : Color.cyan))
                            }
                        }
                        Text("Variazione = media degli ultimi 7 giorni meno media dei 7 precedenti")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            let points = await healthRepo.fetchBodyWeightHistoryPoints(days: 14)
            guard !points.isEmpty else { return }
            let calendar = Calendar.current
            let split = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .now
            // Per-day averages first, so multiple same-day weigh-ins count once.
            func weeklyAverage(_ subset: [DateValuePoint]) -> Double? {
                guard !subset.isEmpty else { return nil }
                let byDay = Dictionary(grouping: subset) { calendar.startOfDay(for: $0.date) }
                let dayAverages = byDay.values.map { $0.map(\.value).reduce(0, +) / Double($0.count) }
                return dayAverages.reduce(0, +) / Double(dayAverages.count)
            }
            let recent = weeklyAverage(points.filter { $0.date >= split })
            let previous = weeklyAverage(points.filter { $0.date < split })
            average7 = recent ?? previous
            if let recent, let previous { ratePerWeek = recent - previous }
        }
    }
}
