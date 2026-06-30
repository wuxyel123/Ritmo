import SwiftUI
import Charts
import FitSyncCore

struct RecoveryView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @StateObject private var vm = RecoveryViewModel()
    @State private var period: HistoryPeriod = .week
    @State private var showingLogView = false
    @State private var editingSession: SleepSession? = nil

    private var sorted: [SleepSession] {
        vm.allSleepSessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FitSyncTheme.gap) {

                    // MARK: Tonight's sleep — always shown inline
                    if vm.allSleepSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, session in
                            SleepSessionCard(
                                session: session,
                                index: sorted.count > 1 ? idx + 1 : nil,
                                onEdit: {
                                    editingSession = session
                                    showingLogView = true
                                },
                                onDelete: {
                                    Task {
                                        try? await healthRepo.deleteSleep(for: session.endTime)
                                        await vm.reload(healthRepo: healthRepo, days: period.days)
                                    }
                                }
                            )
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
                        Task { await vm.reload(healthRepo: healthRepo, days: p.days) }
                    }

                    // MARK: Sleep history chart
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
                }
                .padding(FitSyncTheme.pagePadding)
            }
            .navigationTitle("Recupero")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingLogView = true
                    } label: {
                        Image(systemName: "bed.double.fill")
                        Text("Registra")
                    }
                }
            }
            .sheet(isPresented: $showingLogView, onDismiss: { editingSession = nil }) {
                SleepLogView(
                    editing: editingSession,
                    onSaved: {
                        Task { await vm.reload(healthRepo: healthRepo, days: period.days) }
                    }
                )
            }
            .task {
                await vm.reload(healthRepo: healthRepo, days: period.days)
            }
            .refreshable {
                await vm.reload(healthRepo: healthRepo, days: period.days)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("😴").font(.system(size: 56))
            Text("Nessun dato sonno stanotte")
                .font(.title3.bold())
            Text("Assicurati che iPhone o Apple Watch registri il sonno automaticamente, oppure aggiungilo manualmente.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.horizontal)
    }
}

// MARK: - ViewModel

@MainActor
final class RecoveryViewModel: ObservableObject {
    @Published var allSleepSessions: [SleepSession] = []
    @Published var sleepHistory: [SleepSession] = []

    func reload(healthRepo: HealthKitRepository, days: Int) async {
        let chartDays = min(days, 30)
        var arr: [SleepSession] = []
        for i in 0..<chartDays {
            if let d = Calendar.current.date(byAdding: .day, value: -i, to: .now),
               let s = await healthRepo.fetchSleep(for: d) {
                arr.append(s)
            }
        }
        sleepHistory     = arr
        allSleepSessions = await healthRepo.fetchAllSleepSessions(for: .now)
    }
}
