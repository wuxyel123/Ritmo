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

                    // MARK: Recovery (sleep + heart) — separate from sleep score
                    if let recovery = vm.recovery {
                        RecoveryCard(recovery: recovery)
                    }

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
    @Published var recovery: RecoveryScore?

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
        recovery         = await healthRepo.fetchRecovery()
    }
}

// MARK: - Recovery Card

struct RecoveryCard: View {
    let recovery: RecoveryScore

    private var color: Color {
        switch recovery.status {
        case .poor:      return .red
        case .fair:      return .orange
        case .good:      return .yellow
        case .excellent: return .green
        }
    }

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: "Recupero")
                    Text("Prontezza di oggi · sonno + cuore (diverso dal punteggio del sonno)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(recovery.overall) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(recovery.overall)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                            Text("/100").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(recovery.status.label))
                            .font(.headline).foregroundStyle(color)
                        component("Sonno", recovery.sleep, FitSyncTheme.sleep)
                        if recovery.hasHeartData {
                            component("HRV", recovery.hrv, .green)
                            component("FC riposo", recovery.restingHR, .red)
                        } else {
                            Text("Aggiungi HRV e FC a riposo per un punteggio completo")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func component(_ label: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.2)).frame(height: 5)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(value, 100)) / 100, height: 5)
                }
            }
            .frame(height: 5)
            Text("\(value)").font(.caption2.bold()).frame(width: 26, alignment: .trailing)
        }
    }
}
