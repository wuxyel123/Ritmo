import SwiftUI
import SwiftData
import RitmoCore

enum ActivityMetricKind {
    case activeCalories, steps

    var title: String   { self == .activeCalories ? "Calorie attive" : "Passi" }
    var unit: String    { self == .activeCalories ? "kcal" : "" }
    var icon: String    { self == .activeCalories ? "bolt.fill" : "figure.walk" }
    var color: Color    { self == .activeCalories ? .red : RitmoTheme.steps }
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
                VStack(spacing: RitmoTheme.gap) {

                    // Stats strip
                    HStack(spacing: 0) {
                        statPill(label: "Media", value: formatted(avg), color: metric.color)
                        Divider().frame(height: 40)
                        statPill(label: "Massimo", value: formatted(maxVal), color: .primary)
                        Divider().frame(height: 40)
                        statPill(label: "Giorni obiettivo", value: "\(daysOnGoal)/\(history.count)", color: goal > 0 ? .green : .secondary)
                    }
                    .padding(.vertical, 6)
                    .background(RitmoTheme.cardBG, in: RoundedRectangle(cornerRadius: RitmoTheme.cardRadius))

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
                .padding(RitmoTheme.pagePadding)
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
