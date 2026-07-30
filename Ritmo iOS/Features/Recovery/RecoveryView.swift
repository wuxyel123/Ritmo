import SwiftUI
import Charts
import RitmoCore

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
                VStack(spacing: RitmoTheme.gap) {

                    // MARK: Recovery (sleep + heart) — separate from sleep score
                    if let recovery = vm.recovery {
                        RecoveryCard(recovery: recovery,
                                     hasSleepData: !vm.allSleepSessions.isEmpty)
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

                    // MARK: Sleep history chart — interactive (tap/drag to
                    // inspect a night, expandable), 12h axis; values clamped
                    // so an outlier night can't draw past the plot area.
                    if !vm.sleepHistory.isEmpty {
                        InteractiveDateChart(
                            title: "Ore di sonno",
                            points: vm.sleepHistory.map {
                                ChartPoint(date: $0.startTime, value: min($0.totalHours, 12))
                            },
                            goal: 8,
                            color: RitmoTheme.sleep,
                            unit: "h",
                            chartUnit: .day,
                            chartType: .bar,
                            yDomain: 0...12,
                            decimals: 1
                        )
                    }
                }
                .padding(RitmoTheme.pagePadding)
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
    var hasSleepData: Bool = true
    var showsInfo: Bool = true
    @State private var showingInfo = false

    private var color: Color {
        guard hasSleepData else { return .secondary }
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader(title: "Recupero")
                        Text("Prontezza di oggi · sonno + cuore (diverso dal punteggio del sonno)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if showsInfo {
                        Spacer()
                        Button { showingInfo = true } label: {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: hasSleepData ? CGFloat(recovery.overall) / 100 : 0)
                            .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(hasSleepData ? "\(recovery.overall)" : "—")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                            Text("/100").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 6) {
                        // Without tonight's sleep there is no score to judge:
                        // a red "0 · Scarso" would grade missing data.
                        if hasSleepData {
                            Text(LocalizedStringKey(recovery.status.label))
                                .font(.headline).foregroundStyle(color)
                            component("Sonno", recovery.sleep, RitmoTheme.sleep)
                            if recovery.hasHeartData {
                                component("HRV", recovery.hrv, .green)
                                component("FC riposo", recovery.restingHR, .red)
                            } else {
                                Text("Aggiungi HRV e FC a riposo per un punteggio completo")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Nessun dato")
                                .font(.headline).foregroundStyle(.secondary)
                            Text("Registra il sonno di stanotte per calcolare il recupero.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .alert("Come si calcola il recupero?", isPresented: $showingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Il recupero (0–100) stima quanto sei pronto per oggi combinando:\n\n• Qualità del sonno di stanotte (65%)\n• HRV rispetto alla tua media di 28 giorni (20%)\n• Frequenza cardiaca a riposo vs la tua media (15%)\n\nHRV più alta e FC a riposo più bassa = recupero migliore. Senza dati cardiaci si usa solo il sonno. È diverso dal punteggio del sonno, che valuta la sola notte.")
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
