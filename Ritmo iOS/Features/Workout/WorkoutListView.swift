import SwiftUI
import SwiftData
import Charts
import RitmoCore

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @State private var isSyncing = false
    @State private var pendingDelete: WorkoutSession?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyWorkoutView(onSync: { Task { await syncHealthKit() } })
                } else {
                    List {
                        NavigationLink {
                            TrainingLoadDetailView(sessions: sessions)
                        } label: {
                            TrainingLoadCard(load: TrainingLoad.compute(from: sessions))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        ForEach(sessions) { session in
                            NavigationLink(destination: WorkoutDetailView(session: session)) {
                                if session.source == .healthKit {
                                    HealthKitWorkoutRow(session: session)
                                } else {
                                    WorkoutRow(session: session)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = session
                                } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .confirmationDialog("Eliminare l'allenamento?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                presenting: pendingDelete) { session in
                if session.source == .manual {
                    Button("Elimina allenamento", role: .destructive) {
                        remove(session, alsoFromHealth: true)
                    }
                } else if session.source == .hevy {
                    Button("Elimina allenamento", role: .destructive) {
                        remove(session, alsoFromHealth: false)
                    }
                } else {
                    Button("Rimuovi solo dall'app", role: .destructive) {
                        remove(session, alsoFromHealth: false)
                    }
                    Button("Elimina anche da Apple Salute", role: .destructive) {
                        remove(session, alsoFromHealth: true)
                    }
                }
                Button("Annulla", role: .cancel) { pendingDelete = nil }
            } message: { session in
                if session.source == .manual {
                    Text("L'allenamento verrà eliminato anche da Apple Salute.")
                } else if session.source == .hevy {
                    Text("L'allenamento importato da Hevy verrà rimosso dall'app.")
                } else {
                    Text("«Solo dall'app» lo nasconde ma resta in Apple Salute. «Elimina anche da Apple Salute» funziona solo per allenamenti creati da Ritmo.")
                }
            }
            .navigationTitle("Allenamenti")
            .task { await syncHealthKit() }
            .refreshable { await syncHealthKit() }
        }
    }

    private func remove(_ session: WorkoutSession, alsoFromHealth: Bool) {
        let uuid = session.hkWorkoutUUID
        // App-authored workouts always take their HealthKit record with them —
        // Ritmo owns it, and leaving it behind would ghost-count the workout.
        let deleteFromHealth = alsoFromHealth || session.source == .manual
        pendingDelete = nil
        // Remove locally FIRST so it disappears immediately, regardless of the
        // HealthKit outcome (Apple-owned workouts can't be deleted by us).
        healthRepo.deleteWorkout(session, in: modelContext)   // exclude + local delete
        GoalsSyncService.shared.sendExcludedWorkouts(Array(HealthKitRepository.excludedWorkoutUUIDs()))
        pushTrainingLoad()
        if deleteFromHealth, let uuid {
            Task { _ = await healthRepo.deleteHealthKitWorkout(uuid: uuid) }
        }
    }

    /// Recomputes training load from the freshly-saved store and pushes it to
    /// the Watch — the iPhone is the source of truth, so both devices agree.
    private func pushTrainingLoad() {
        let fresh = (try? modelContext.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        )) ?? []
        GoalsSyncService.shared.sendTrainingLoad(TrainingLoad.compute(from: fresh))
    }

    /// HealthKit first; only when it inserted NEW workouts does the Hevy API
    /// get asked, to complete those sessions with sets/title (never duplicate).
    private func syncHealthKit() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        if await healthRepo.importHealthKitWorkouts(into: modelContext) > 0 {
            await HevySyncCoordinator.enrichNewWorkouts(into: modelContext)
        }
        pushTrainingLoad()
    }

}

// MARK: - Training Load Card

struct TrainingLoadCard: View {
    let load: TrainingLoad

    private var color: Color {
        switch load.status {
        case .low:      return .blue
        case .optimal:  return .green
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SectionHeader(title: "Carico allenamento")
                    Spacer()
                    Text(LocalizedStringKey(load.status.label))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(load.acute)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("carico 7 giorni").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("media \(load.chronic)").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    let maxV = max(load.weeklyEfforts.max() ?? 1, 1)
                    ForEach(Array(load.weeklyEfforts.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(v > 0 ? color : Color.gray.opacity(0.2))
                            .frame(height: max(4, CGFloat(v) / CGFloat(maxV) * 34))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 34)
            }
        }
    }
}

// MARK: - Training Load Detail

struct TrainingLoadDetailView: View {
    let sessions: [WorkoutSession]

    // Every aggregate below is a full pass over the whole session store; as
    // computed properties they re-ran on EVERY body evaluation (history alone
    // was read several times per pass) — the lag when opening this screen.
    // Computed once instead, right after the push animation starts.
    @State private var load: TrainingLoad?
    @State private var history: [TrainingLoadPoint] = []
    @State private var categoryLoads: [CategoryLoad] = []
    @State private var daily: [(date: Date, load: Int)] = []

    private func statusColor(_ status: TrainingLoadStatus) -> Color {
        switch status {
        case .low:      return .blue
        case .optimal:  return .green
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }

    // Data only, per explicit user preference: state which band the ratio is
    // in, no advice ("valuta una giornata più leggera") or judgment.
    private func statusExplanation(_ status: TrainingLoadStatus) -> String {
        switch status {
        case .low:
            return "Il carico degli ultimi 7 giorni è sotto l'80% della tua media di 4 settimane."
        case .optimal:
            return "Il carico degli ultimi 7 giorni è tra l'80% e il 130% della tua media di 4 settimane."
        case .high:
            return "Il carico degli ultimi 7 giorni è tra il 130% e il 150% della tua media di 4 settimane."
        case .veryHigh:
            return "Il carico degli ultimi 7 giorni è oltre il 150% della tua media di 4 settimane."
        }
    }

    private func categoryColor(_ c: WorkoutCategory) -> Color {
        switch c {
        case .strength: return .purple
        case .cardio:   return .orange
        case .other:    return .gray
        }
    }

    private func dailyLoad(days: Int) -> [(date: Date, load: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<days).reversed().compactMap { offset in
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let v = sessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
                .reduce(0.0) { $0 + $1.loadValue }
            return (dayStart, Int(v.rounded()))
        }
    }

    var body: some View {
        ScrollView {
            if let load {
                content(load)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .navigationTitle("Carico allenamento")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard load == nil else { return }
            history = TrainingLoad.history(from: sessions)
            categoryLoads = TrainingLoad.loadByCategory(from: sessions)
            daily = dailyLoad(days: 14)
            load = TrainingLoad.compute(from: sessions)   // last: flips the view
        }
    }

    @ViewBuilder
    private func content(_ load: TrainingLoad) -> some View {
        let color = statusColor(load.status)
        VStack(alignment: .leading, spacing: RitmoTheme.gap) {

                // MARK: Header
                FitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Carico 7 giorni").font(.caption).foregroundStyle(.secondary)
                                Text("\(load.acute)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(color)
                                Text("punteggio · sforzo × durata")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(LocalizedStringKey(load.status.label))
                                    .font(.headline).foregroundStyle(color)
                                Text("media 4 sett.: \(load.chronic)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if load.chronic > 0 {
                                    Text(String(format: "%.0f%% della media", load.ratio * 100))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(statusExplanation(load.status)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // MARK: Daily load chart (14 days)
                FitCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Carico giornaliero")
                        Chart(daily, id: \.date) { item in
                            BarMark(x: .value("Giorno", item.date, unit: .day),
                                    y: .value("Carico", item.load),
                                    width: .fixed(10))
                                .foregroundStyle(color.gradient)
                                .cornerRadius(3)
                        }
                        .frame(height: 130)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) {
                                AxisValueLabel(format: .dateTime.day())
                            }
                        }
                    }
                }

                // MARK: Acute:chronic ratio trend
                if history.count > 1 {
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Andamento del rapporto")
                            Text("Carico recente (7gg) rispetto alla tua media di 4 settimane — 100% = in linea con la norma")
                                .font(.caption2).foregroundStyle(.secondary)
                            let percentages = history.map { $0.ratio * 100 }
                            let upperBound = max(160, (percentages.max() ?? 160) * 1.1)
                            let bandEnd = history.last!.date
                            let bandStart = history.first!.date
                            Chart {
                                RectangleMark(xStart: .value("Inizio", bandStart), xEnd: .value("Fine", bandEnd),
                                              yStart: .value("Da", 0.0), yEnd: .value("A", 80.0))
                                    .foregroundStyle(Color.blue.opacity(0.10))
                                RectangleMark(xStart: .value("Inizio", bandStart), xEnd: .value("Fine", bandEnd),
                                              yStart: .value("Da", 80.0), yEnd: .value("A", 130.0))
                                    .foregroundStyle(Color.green.opacity(0.10))
                                RectangleMark(xStart: .value("Inizio", bandStart), xEnd: .value("Fine", bandEnd),
                                              yStart: .value("Da", 130.0), yEnd: .value("A", 150.0))
                                    .foregroundStyle(Color.orange.opacity(0.10))
                                RectangleMark(xStart: .value("Inizio", bandStart), xEnd: .value("Fine", bandEnd),
                                              yStart: .value("Da", 150.0), yEnd: .value("A", upperBound))
                                    .foregroundStyle(Color.red.opacity(0.10))
                                RuleMark(y: .value("Base", 100.0))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(.secondary)
                                ForEach(history) { p in
                                    LineMark(x: .value("Giorno", p.date), y: .value("Rapporto", p.ratio * 100))
                                        .interpolationMethod(.catmullRom)
                                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                                        .foregroundStyle(color)
                                }
                            }
                            .chartYScale(domain: 0...upperBound)
                            .frame(height: 140)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 14)) {
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let v = value.as(Double.self) {
                                            Text("\(Int(v))%")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: Load by category
                if !categoryLoads.isEmpty {
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Ripartizione per tipo")
                            Text("Da dove viene il carico, ultimi 28 giorni")
                                .font(.caption2).foregroundStyle(.secondary)
                            let total = max(categoryLoads.reduce(0) { $0 + $1.load }, 1)
                            ForEach(categoryLoads) { c in
                                let pct = c.load / total
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(LocalizedStringKey(c.category.displayName)).font(.caption)
                                        Spacer()
                                        Text("\(Int((pct * 100).rounded()))%")
                                            .font(.caption.bold()).foregroundStyle(categoryColor(c.category))
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(categoryColor(c.category).opacity(0.15)).frame(height: 6)
                                            Capsule().fill(categoryColor(c.category))
                                                .frame(width: geo.size.width * CGFloat(pct), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                    }
                }

                // MARK: How it's calculated
                FitCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Come si calcola")
                        Text("Ogni allenamento riceve uno sforzo da 1 a 10 (RPE): per la forza si basa sulla durata (in zona 1 ma alta intensità), per il cardio sull'intensità delle calorie. Puoi impostare tu l'RPE su ogni allenamento.\n\nIl carico di un allenamento = sforzo × durata (metodo «session-RPE»). Confrontiamo la fatica recente (media mobile pesata a ~7 giorni) con la forma di lungo periodo (~28 giorni): il loro rapporto (ACWR) dice se stai caricando in modo equilibrato. La zona ideale è circa 0,8–1,3× la tua media; oltre 1,5× aumenta il rischio di infortunio.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
        }
        .padding(RitmoTheme.pagePadding)
    }
}
