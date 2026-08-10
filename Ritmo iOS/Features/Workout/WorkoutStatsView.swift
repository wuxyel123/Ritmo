import SwiftUI
import SwiftData
import Charts
import RitmoCore

// MARK: - WorkoutStatsView
//
// The Statistiche hub inside Allenamenti: weekly working sets per muscle
// group, weekly tonnage, rep-range mix, muscle-group frequency, session
// density, relative strength (e1RM ÷ body weight) and the per-exercise
// progression browser. Everything is stated as data — no judgments.
//
// All aggregates are full passes over the session store, so they're computed
// ONCE in .task into `stats` (the TrainingLoadDetailView lesson: computed
// properties re-run per body evaluation and stutter the push animation).

enum StatsSection {
    case gym, cardio
}

struct WorkoutStatsView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \RaceResult.date, order: .reverse) private var races: [RaceResult]
    @Query private var storedGoals: [UserGoals]
    @AppStorage("oplUsername") private var oplUsername = ""

    private struct Stats {
        var weeklySetsAll: [WorkoutStats.WeekPoint] = []
        var groupsWithSets: [MuscleGroup] = []
        var tonnage: [WorkoutStats.WeekPoint] = []
        var repSplit = WorkoutStats.RepRangeSplit(strength: 0, hypertrophy: 0, endurance: 0)
        var frequency: [WorkoutStats.GroupFrequency] = []
        var density: [DateValuePoint] = []
        var exercises: [WorkoutStats.ExerciseSummary] = []
        var bodyWeights: [DateValuePoint] = []
        // Cardio
        var runPBs: [EnduranceStats.PersonalBest] = []
        var ridePBs: [EnduranceStats.PersonalBest] = []
        var weeklyRunKm: [WorkoutStats.WeekPoint] = []
        var weeklyRideKm: [WorkoutStats.WeekPoint] = []
        var runEquivalents: [EnduranceStats.EquivalentTime] = []
        var loadRatioPct: Int?          // for the meet countdown card
    }

    struct RoutineRow: Identifiable {
        let id = UUID()
        let title: String
        let exerciseCount: Int
        let setCount: Int
        let lastDone: Date?
        let count30: Int
    }

    @State private var stats: Stats?
    @State private var setsGroupFilter: MuscleGroup?          // nil = all groups
    @State private var setsForFilter: [WorkoutStats.WeekPoint] = []
    @State private var oplMeets: [OPLMeet] = []
    @State private var oplEvents: [String] = []              // distinct, SBD first
    @State private var oplEventFilter = "SBD"
    @State private var oplGLPoints: [DateValuePoint] = []   // selected event's series, oldest → newest
    @State private var oplMetricLabel = "punti IPF"          // "punti IPF" | "punti Dots" | "kg"
    @State private var oplError: String?
    @State private var section: StatsSection = .gym
    @State private var kmSport: EnduranceStats.Sport = .run
    @State private var showingRaceEditor = false
    @State private var stravaImportError: String?
    @State private var routineRows: [RoutineRow] = []
    @AppStorage("meetDateEpoch") private var meetDateEpoch = 0.0
    @AppStorage("hevyConnected") private var hevyConnected = false
    @AppStorage("hevyApiKey") private var hevyApiKey = ""

    var body: some View {
        ScrollView {
            if let stats {
                VStack(alignment: .leading, spacing: RitmoTheme.gap) {
                    Picker("Sezione", selection: $section) {
                        Text("Palestra").tag(StatsSection.gym)
                        Text("Cardio").tag(StatsSection.cardio)
                    }
                    .pickerStyle(.segmented)

                    recordsLinkCard

                    switch section {
                    case .gym:
                        meetCountdownCard(stats)
                        weeklySetsCard(stats)
                        tonnageCard(stats)
                        repRangeCard(stats)
                        frequencyCard(stats)
                        densityCard(stats)
                        relativeStrengthCard(stats)
                        compMaxCard(stats)
                        routinesCard
                        oplCard
                        exercisesCard(stats)
                    case .cardio:
                        pbCard(stats, sport: .run)
                        pbCard(stats, sport: .ride)
                        riegelCard(stats)
                        weeklyKmCard(stats)
                        racesCard
                    }
                }
                .padding(RitmoTheme.pagePadding)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .sheet(isPresented: $showingRaceEditor) {
            RaceEditorView()
        }
        .onChange(of: races.count) { _, _ in recomputeCardio() }
        .navigationTitle("Statistiche")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard stats == nil else { return }
            var s = Stats()
            s.weeklySetsAll = WorkoutStats.weeklySets(from: sessions)
            s.tonnage = WorkoutStats.weeklyTonnage(from: sessions)
            s.repSplit = WorkoutStats.repRangeSplit(from: sessions)
            s.frequency = WorkoutStats.muscleGroupFrequency(from: sessions)
            s.density = WorkoutStats.sessionDensity(from: sessions)
            s.exercises = WorkoutStats.exerciseSummaries(from: sessions)
            s.groupsWithSets = s.frequency.map(\.group)
            s.bodyWeights = await healthRepo.fetchBodyWeightHistoryPoints(days: 365)
            s.runPBs = EnduranceStats.personalBests(sport: .run, sessions: sessions, races: races)
            s.ridePBs = EnduranceStats.personalBests(sport: .ride, sessions: sessions, races: races)
            s.weeklyRunKm = EnduranceStats.weeklyDistanceKm(sport: .run, from: sessions)
            s.weeklyRideKm = EnduranceStats.weeklyDistanceKm(sport: .ride, from: sessions)
            s.runEquivalents = EnduranceStats.riegelEquivalents(from: s.runPBs)
            s.loadRatioPct = Int((TrainingLoad.compute(from: sessions).ratio * 100).rounded())
            setsForFilter = s.weeklySetsAll
            stats = s
            // Hevy routines (read-only: templates + when each was last done).
            if hevyConnected, !hevyApiKey.isEmpty,
               let routines = try? await HevyService(apiKey: hevyApiKey).fetchRoutines() {
                let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
                routineRows = routines.map { routine in
                    let matching = sessions.filter { $0.title == routine.title }
                    return RoutineRow(title: routine.title,
                                      exerciseCount: routine.exerciseCount,
                                      setCount: routine.setCount,
                                      lastDone: matching.map(\.startTime).max(),
                                      count30: matching.filter { $0.startTime >= cutoff }.count)
                }
            }
            // Strava: pull any new race-tagged activities, then refresh PBs.
            if StravaSession.isConnected {
                do {
                    if try await StravaSession.importNewRaces(into: modelContext) > 0 {
                        recomputeCardio()
                    }
                } catch {
                    stravaImportError = error.localizedDescription
                }
            }
            if !oplUsername.isEmpty {
                do {
                    oplMeets = try await OpenPowerliftingService.fetchMeets(username: oplUsername)
                    // Distinct events, SBD first: GL points from a bench-only
                    // meet use different coefficients — mixing them in one
                    // line would compare incomparable numbers.
                    var seen: [String] = []
                    for meet in oplMeets where !meet.event.isEmpty && !seen.contains(meet.event) {
                        seen.append(meet.event)
                    }
                    oplEvents = seen.sorted { a, b in
                        if a == "SBD" { return true }
                        if b == "SBD" { return false }
                        return a < b
                    }
                    selectOPLEvent(oplEvents.first ?? "SBD")
                } catch {
                    oplError = error.localizedDescription
                }
            }
        }
    }

    // MARK: Weekly working sets (per muscle group)

    private func weeklySetsCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Serie settimanali")
                    Spacer()
                    Menu {
                        Button("Tutti i gruppi") { selectSetsGroup(nil) }
                        ForEach(s.groupsWithSets, id: \.self) { group in
                            Button { selectSetsGroup(group) } label: {
                                Text(LocalizedStringKey(group.rawValue))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey(setsGroupFilter?.rawValue ?? "Tutti i gruppi"))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(setsGroupFilter.map(muscleColor) ?? RitmoTheme.accent)
                    }
                }
                Text("Serie effettive per settimana (riscaldamento escluso)")
                    .font(.caption2).foregroundStyle(.secondary)
                SelectableStatChart(points: setsForFilter.map { DateValuePoint(date: $0.weekStart, value: $0.value) },
                                    isBar: true, weekly: true, barWidth: 18,
                                    color: setsGroupFilter.map(muscleColor) ?? RitmoTheme.accent)
            }
        }
    }

    private func selectSetsGroup(_ group: MuscleGroup?) {
        setsGroupFilter = group
        setsForFilter = group == nil
            ? (stats?.weeklySetsAll ?? [])
            : WorkoutStats.weeklySets(from: sessions, group: group)
    }

    // MARK: Weekly tonnage

    private func tonnageCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Tonnellaggio settimanale")
                Text("Chili totali sollevati (peso × ripetizioni), ultime 12 settimane")
                    .font(.caption2).foregroundStyle(.secondary)
                SelectableStatChart(points: s.tonnage.map { DateValuePoint(date: $0.weekStart, value: $0.value) },
                                    isBar: true, weekly: true, barWidth: 12, xAxisWeekStride: 2,
                                    kiloYAxis: true, color: RitmoTheme.workout, unit: " kg")
            }
        }
    }

    // MARK: Rep ranges

    private func repRangeCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Distribuzione ripetizioni")
                Text("Serie effettive per fascia di ripetizioni, ultimi 28 giorni")
                    .font(.caption2).foregroundStyle(.secondary)
                if s.repSplit.total == 0 {
                    Text("Nessuna serie nel periodo")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    repRangeRow(label: "1–5 (forza)", count: s.repSplit.strength,
                                total: s.repSplit.total, color: .red)
                    repRangeRow(label: "6–12 (ipertrofia)", count: s.repSplit.hypertrophy,
                                total: s.repSplit.total, color: RitmoTheme.workout)
                    repRangeRow(label: "13+ (resistenza)", count: s.repSplit.endurance,
                                total: s.repSplit.total, color: .mint)
                }
            }
        }
    }

    private func repRangeRow(label: LocalizedStringKey, count: Int, total: Int, color: Color) -> some View {
        let share = Double(count) / Double(max(total, 1))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: NSLocalizedString("%@ serie · %@", comment: ""),
                            "\(count)", "\(Int((share * 100).rounded()))%"))
                    .font(.caption.bold()).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(share), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Muscle-group frequency

    private func frequencyCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Frequenza per gruppo muscolare")
                Text("Giorni di allenamento per gruppo, ultimi 28 giorni")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(s.frequency.prefix(8)) { item in
                    HStack {
                        Text(LocalizedStringKey(item.group.rawValue))
                            .font(.caption)
                            .foregroundStyle(muscleColor(item.group))
                            .frame(width: 100, alignment: .leading)
                        Text(String(format: NSLocalizedString("%@×/settimana", comment: ""),
                                    String(format: "%.1f", item.perWeek)))
                            .font(.caption.bold())
                        Spacer()
                        if let gap = item.averageGapDays {
                            Text(String(format: NSLocalizedString("ogni %@ giorni", comment: ""),
                                        String(format: "%.1f", gap)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Session density

    private func densityCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Densità di sessione")
                Text("kg al minuto per sessione, ultimi 90 giorni")
                    .font(.caption2).foregroundStyle(.secondary)
                if s.density.count < 2 {
                    Text("Servono più sessioni con serie registrate")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    SelectableStatChart(points: s.density, color: RitmoTheme.workout,
                                        decimals: 1, unit: " kg/min", height: 130)
                }
            }
        }
    }

    // MARK: Relative strength (IPF GL points — real data only)
    //
    // OpenPowerlifting meets when connected (OPL scores GL with the ACTUAL
    // meet-day body weight — the authoritative number), the manually entered
    // comp maxes otherwise. No estimated-e1RM totals here: Epley estimates
    // run higher than real maxes and made the chart disagree with meet data.

    /// Recomputed only on selection — GL coefficients differ per event, so
    /// each event gets its own comparable series. The IPF GL formula only
    /// exists for full meets and bench: squat/deadlift-only events have no
    /// Goodlift on OPL, so they fall back to Dots points (defined for every
    /// event), then to raw kg — the card must never vanish under a selection.
    private func selectOPLEvent(_ event: String) {
        oplEventFilter = event
        let meets = oplMeets.filter { $0.event == event }

        let gl = meets.compactMap { m in m.goodlift.map { DateValuePoint(date: m.date, value: $0) } }
        if !gl.isEmpty {
            oplGLPoints = gl.sorted { $0.date < $1.date }
            oplMetricLabel = "punti IPF"
            return
        }
        let dots = meets.compactMap { m in m.dots.map { DateValuePoint(date: m.date, value: $0) } }
        if !dots.isEmpty {
            oplGLPoints = dots.sorted { $0.date < $1.date }
            oplMetricLabel = "punti Dots"
            return
        }
        oplGLPoints = meets
            .compactMap { m in m.totalKg.map { DateValuePoint(date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
        oplMetricLabel = "kg"
    }

    private var oplSubtitle: String {
        switch oplMetricLabel {
        case "punti Dots":
            return "Punti Dots delle tue gare (OpenPowerlifting) — per le gare di singola alzata l'IPF GL non è definito"
        case "kg":
            return "Chili sollevati nelle tue gare (OpenPowerlifting)"
        default:
            return "Punti IPF GL delle tue gare (OpenPowerlifting)"
        }
    }

    @ViewBuilder
    private func relativeStrengthCard(_ s: Stats) -> some View {
        // Card + event picker stay as long as OPL data exists — a selection
        // with no chartable points must not make the picker disappear.
        if !oplMeets.isEmpty {
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Forza relativa")
                        Spacer()
                        if oplEvents.count > 1 {
                            Menu {
                                ForEach(oplEvents, id: \.self) { event in
                                    Button { selectOPLEvent(event) } label: {
                                        Text(LocalizedStringKey(eventLabel(event)))
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(eventLabel(oplEventFilter)))
                                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                                }
                                .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                            }
                        }
                    }
                    Text(LocalizedStringKey(oplSubtitle))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let latest = oplGLPoints.last {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", latest.value))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(RitmoTheme.accent)
                            Text(LocalizedStringKey(oplMetricLabel))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(latest.date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if oplGLPoints.count >= 2 {
                            SelectableStatChart(points: oplGLPoints, decimals: 1,
                                                yDomain: glDomain, height: 130)
                        }
                    } else {
                        Text("Nessun punteggio disponibile per questo tipo di gara")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else if let goals = storedGoals.first,
                  goals.compSquatKg > 0, goals.compBenchKg > 0, goals.compDeadliftKg > 0,
                  let bw = s.bodyWeights.last?.value, bw > 0 {
            let total = goals.compSquatKg + goals.compBenchKg + goals.compDeadliftKg
            let points = WorkoutStats.ipfGLPoints(total: total, bodyWeightKg: bw,
                                                  isFemale: healthRepo.isFemale() ?? false)
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Forza relativa")
                    Text("Punti IPF GL dai massimali gara inseriti, al peso corporeo attuale")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", points))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(RitmoTheme.accent)
                        Text("punti IPF").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: NSLocalizedString("totale %@ kg · %@ kg BW", comment: ""),
                                    fmtKg(total), fmtKg(bw)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var glDomain: ClosedRange<Double> {
        let values = oplGLPoints.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 2)
        return max(lo - pad, 0)...(hi + pad)
    }

    // MARK: Competition maxes — OpenPowerlifting when connected, else the
    // manually entered values (Impostazioni → Powerlifting)

    /// Best training e1RM for one competition lift (both IT/EN catalog names).
    private func estimatedE1RM(for lift: WorkoutStats.SBDLift, in s: Stats) -> Double? {
        let best = s.exercises
            .filter { WorkoutStats.SBDLift.classify($0.name) == lift }
            .map(\.bestE1RM)
            .max() ?? 0
        return best > 0 ? best : nil
    }

    @ViewBuilder
    private func compMaxCard(_ s: Stats) -> some View {
        // Totals and GL points only from FULL meets: a bench-only meet's
        // "total" is just the bench, and its GL uses other coefficients.
        let fullMeets = oplMeets.filter { $0.event == "SBD" }
        if !oplMeets.isEmpty {
            let lifts: [(String, Double, Double?)] = [
                ("Squat", oplMeets.compactMap(\.bestSquatKg).max() ?? 0, estimatedE1RM(for: .squat, in: s)),
                ("Panca Piana", oplMeets.compactMap(\.bestBenchKg).max() ?? 0, estimatedE1RM(for: .bench, in: s)),
                ("Stacco da Terra", oplMeets.compactMap(\.bestDeadliftKg).max() ?? 0, estimatedE1RM(for: .deadlift, in: s))]
            compMaxContent(lifts: lifts,
                           bestTotal: fullMeets.compactMap(\.totalKg).max(),
                           bestGL: fullMeets.compactMap(\.goodlift).max(),
                           source: "Migliori alzate di gara (OpenPowerlifting) · stima = 1RM dagli allenamenti")
        } else if let goals = storedGoals.first,
                  goals.compSquatKg > 0 || goals.compBenchKg > 0 || goals.compDeadliftKg > 0 {
            let lifts: [(String, Double, Double?)] = [
                ("Squat", goals.compSquatKg, estimatedE1RM(for: .squat, in: s)),
                ("Panca Piana", goals.compBenchKg, estimatedE1RM(for: .bench, in: s)),
                ("Stacco da Terra", goals.compDeadliftKg, estimatedE1RM(for: .deadlift, in: s))]
            let allSet = lifts.allSatisfy { $0.1 > 0 }
            compMaxContent(lifts: lifts,
                           bestTotal: allSet ? lifts.map(\.1).reduce(0, +) : nil,
                           bestGL: nil,
                           source: "Massimali inseriti manualmente · stima = 1RM dagli allenamenti")
        }
    }

    private func compMaxContent(lifts: [(String, Double, Double?)], bestTotal: Double?,
                                bestGL: Double?, source: String) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Massimali gara")
                Text(LocalizedStringKey(source))
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(lifts, id: \.0) { name, kg, estimate in
                        VStack(spacing: 3) {
                            Text(kg > 0 ? fmtKg(kg) : "—")
                                .font(.title3.bold())
                                .foregroundStyle(kg > 0 ? RitmoTheme.workout : .secondary)
                            Text(LocalizedStringKey(name))
                                .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                            if let estimate, kg > 0 {
                                let deltaPct = (estimate - kg) / kg * 100
                                Text(String(format: NSLocalizedString("stima %@ (%@)", comment: ""),
                                            fmtKg(estimate),
                                            String(format: "%+.0f%%", deltaPct)))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if bestTotal != nil || bestGL != nil {
                    Divider()
                    HStack {
                        if let bestTotal {
                            Text("Totale").font(.caption).foregroundStyle(.secondary)
                            Text("\(fmtKg(bestTotal)) kg").font(.subheadline.bold())
                        }
                        Spacer()
                        if let bestGL {
                            Text(String(format: NSLocalizedString("%@ punti IPF", comment: ""),
                                        String(format: "%.1f", bestGL)))
                                .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: OpenPowerlifting meets

    @ViewBuilder
    private var oplCard: some View {
        if !oplUsername.isEmpty {
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Gare (OpenPowerlifting)")
                    if let oplError {
                        Text(oplError).font(.caption).foregroundStyle(.secondary)
                    } else if oplMeets.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 0) {
                            StatItem(value: "\(oplMeets.count)", label: "gare", icon: "trophy")
                        }
                        if let last = oplMeets.first {
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(last.meetName).font(.caption.bold()).lineLimit(1)
                                    Text(last.date, format: .dateTime.day().month(.abbreviated).year())
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let total = last.totalKg {
                                    Text("\(fmtKg(total)) kg").font(.caption.bold())
                                }
                            }
                        }
                        NavigationLink {
                            OPLMeetsView(meets: oplMeets, username: oplUsername)
                        } label: {
                            HStack {
                                Text("Tutte le gare").font(.caption.bold())
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .foregroundStyle(RitmoTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func fmtKg(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    // MARK: - Records / meet countdown / calculator / routines

    private var recordsLinkCard: some View {
        NavigationLink {
            RecordsTimelineView()
        } label: {
            FitCard {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title3).foregroundStyle(.yellow)
                        .frame(width: 38, height: 38)
                        .background(Color.yellow.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Record").font(.subheadline.bold())
                        Text("Cronologia dei tuoi primati — palestra e gare")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func meetCountdownCard(_ s: Stats) -> some View {
        if meetDateEpoch > 0 {
            let meetDate = Date(timeIntervalSince1970: meetDateEpoch)
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: .now),
                to: Calendar.current.startOfDay(for: meetDate)).day ?? -1
            if days >= 0 {
                FitCard {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.title3).foregroundStyle(RitmoTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(RitmoTheme.accent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: NSLocalizedString("Gara tra %@ giorni", comment: ""), "\(days)"))
                                .font(.subheadline.bold())
                            Text(meetDate, format: .dateTime.weekday(.wide).day().month().year())
                                .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                        }
                        Spacer()
                        if let pct = s.loadRatioPct {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(pct)%").font(.subheadline.bold())
                                Text("carico vs media").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }


    @ViewBuilder
    private var routinesCard: some View {
        if !routineRows.isEmpty {
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Routine Hevy")
                    Text("Ultima esecuzione (allenamenti con lo stesso nome della routine)")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(routineRows.prefix(6)) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.caption.bold()).lineLimit(1)
                                Text(String(format: NSLocalizedString("%@ esercizi · %@ serie", comment: ""),
                                            "\(row.exerciseCount)", "\(row.setCount)"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let last = row.lastDone {
                                    Text(last, format: .relative(presentation: .named))
                                        .font(.caption2.bold())
                                } else {
                                    Text("mai eseguita").font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(String(format: NSLocalizedString("×%@ in 30gg", comment: ""),
                                            "\(row.count30)"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if row.id != routineRows.prefix(6).last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func riegelCard(_ s: Stats) -> some View {
        if !s.runEquivalents.isEmpty {
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Tempi equivalenti — Corsa")
                    Text("Formula di Riegel (t × (d₂/d₁)^1,06) applicata al PB della distanza più vicina")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(s.runEquivalents) { equivalent in
                        HStack {
                            Text(LocalizedStringKey(equivalent.bucket.label)).font(.caption.bold())
                            Spacer()
                            Text(String(format: NSLocalizedString("da %@", comment: ""),
                                        NSLocalizedString(equivalent.sourceLabel, comment: "")))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(EnduranceStats.formatDuration(equivalent.seconds))
                                .font(.subheadline.bold())
                                .frame(width: 76, alignment: .trailing)
                        }
                        if equivalent.id != s.runEquivalents.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Cardio

    /// PBs depend on sessions AND the race log — re-run after any race change
    /// (add, delete, Strava import).
    private func recomputeCardio() {
        guard stats != nil else { return }
        stats?.runPBs = EnduranceStats.personalBests(sport: .run, sessions: sessions, races: races)
        stats?.ridePBs = EnduranceStats.personalBests(sport: .ride, sessions: sessions, races: races)
    }

    /// WMA age-grade % for a run at a canonical distance (needs birth date +
    /// sex in the Health profile), nil otherwise.
    private func ageGradePercent(_ gradingDistance: AgeGrading.Distance?,
                                 seconds: Int, date: Date) -> Double? {
        guard let gradingDistance, let age = healthRepo.ageYears(at: date) else { return nil }
        return AgeGrading.percent(distance: gradingDistance,
                                  timeSeconds: Double(seconds),
                                  age: age,
                                  isFemale: healthRepo.isFemale() ?? false)
    }

    @ViewBuilder
    private func pbCard(_ s: Stats, sport: EnduranceStats.Sport) -> some View {
        let pbs = sport == .run ? s.runPBs : s.ridePBs
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: sport == .run ? "Personal best — Corsa" : "Personal best — Bici")
                if pbs.isEmpty {
                    Text("Nessun personal best: servono attività alle distanze classiche o gare registrate.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(pbs) { pb in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(pb.bucket.label)).font(.caption.bold())
                                Text(pb.date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if pb.isRace {
                                Text("gara")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(RitmoTheme.accent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(RitmoTheme.accent)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(EnduranceStats.formatDuration(pb.durationSeconds))
                                    .font(.subheadline.bold())
                                HStack(spacing: 6) {
                                    Text(sport == .run
                                         ? EnduranceStats.formatPace(pb.paceSecondsPerKm) + "/km"
                                         : String(format: "%.1f km/h", pb.speedKmH))
                                        .font(.caption2).foregroundStyle(.secondary)
                                    if let grade = ageGradePercent(pb.bucket.gradingDistance,
                                                                   seconds: pb.durationSeconds,
                                                                   date: pb.date) {
                                        Text(String(format: NSLocalizedString("AG %@", comment: ""),
                                                    String(format: "%.1f%%", grade)))
                                            .font(.caption2.bold()).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        if pb.id != pbs.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func weeklyKmCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Km settimanali")
                    Spacer()
                    Menu {
                        Button("Corsa") { kmSport = .run }
                        Button("Bici") { kmSport = .ride }
                    } label: {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey(kmSport == .run ? "Corsa" : "Bici"))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                    }
                }
                Text("Distanza per settimana, ultime 12 settimane")
                    .font(.caption2).foregroundStyle(.secondary)
                SelectableStatChart(
                    points: (kmSport == .run ? s.weeklyRunKm : s.weeklyRideKm)
                        .map { DateValuePoint(date: $0.weekStart, value: $0.value) },
                    isBar: true, weekly: true, barWidth: 12, xAxisWeekStride: 2,
                    color: kmSport == .run ? .mint : .cyan, decimals: 1, unit: " km")
            }
        }
    }

    private var racesCard: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Gare")
                    Spacer()
                    Button { showingRaceEditor = true } label: {
                        Label("Aggiungi gara", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RitmoTheme.accent)
                }
                if let stravaImportError {
                    Text(stravaImportError).font(.caption2).foregroundStyle(.secondary)
                }
                if races.isEmpty {
                    Text("Nessuna gara registrata")
                        .font(.caption).foregroundStyle(.secondary)
                    if !StravaSession.isConnected {
                        Text("Collega Strava nelle Impostazioni per importare le gare automaticamente.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(races.prefix(5)) { race in
                        raceRow(race)
                        if race.id != races.prefix(5).last?.id { Divider() }
                    }
                    if races.count > 5 {
                        NavigationLink {
                            RaceListView()
                        } label: {
                            HStack {
                                Text("Tutte le gare").font(.caption.bold())
                                Spacer()
                                Text("\(races.count)").font(.caption2).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .foregroundStyle(RitmoTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func raceRow(_ race: RaceResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: race.sport.sfSymbol)
                .font(.caption).foregroundStyle(RitmoTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(race.name.isEmpty ? race.sport.displayName : race.name)
                    .font(.caption.bold()).lineLimit(1)
                Text("\(race.date, format: .dateTime.day().month(.abbreviated).year()) · \(fmtKg(race.distanceMeters / 1000)) km")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(EnduranceStats.formatDuration(race.durationSeconds))
                    .font(.caption.bold())
                if race.sport == .run,
                   let grade = ageGradePercent(AgeGrading.Distance.match(meters: race.distanceMeters),
                                               seconds: race.durationSeconds, date: race.date) {
                    Text(String(format: NSLocalizedString("AG %@", comment: ""),
                                String(format: "%.1f%%", grade)))
                        .font(.caption2.bold()).foregroundStyle(.orange)
                } else {
                    Text(race.sport == .ride
                         ? String(format: "%.1f km/h", race.speedKmH)
                         : EnduranceStats.formatPace(race.paceSecondsPerKm) + "/km")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Exercise browser preview

    private func exercisesCard(_ s: Stats) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Progressione esercizi")
                ForEach(s.exercises.prefix(5)) { exercise in
                    NavigationLink {
                        ExerciseProgressionView(exerciseName: exercise.name)
                    } label: {
                        exerciseRow(exercise)
                    }
                    .buttonStyle(.plain)
                    if exercise.id != s.exercises.prefix(5).last?.id { Divider() }
                }
                if s.exercises.count > 5 {
                    NavigationLink {
                        ExerciseStatsListView(exercises: s.exercises)
                    } label: {
                        HStack {
                            Text("Tutti gli esercizi").font(.caption.bold())
                            Spacer()
                            Text("\(s.exercises.count)")
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .foregroundStyle(RitmoTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func exerciseRow(_ exercise: WorkoutStats.ExerciseSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.subheadline.bold()).lineLimit(1)
                Text(exercise.lastPerformed, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if exercise.bestE1RM > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f kg", exercise.bestE1RM))
                        .font(.subheadline.bold()).foregroundStyle(RitmoTheme.workout)
                    Text("1RM stimato").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - ExerciseStatsListView (all exercises, searchable)

struct ExerciseStatsListView: View {
    let exercises: [WorkoutStats.ExerciseSummary]
    @State private var search = ""

    private var filtered: [WorkoutStats.ExerciseSummary] {
        search.isEmpty ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(filtered) { exercise in
            NavigationLink {
                ExerciseProgressionView(exerciseName: exercise.name)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.subheadline.bold())
                        Text("\(exercise.setCount) serie · \(Int(exercise.totalVolume)) kg")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if exercise.bestE1RM > 0 {
                        Text(String(format: "%.0f kg", exercise.bestE1RM))
                            .font(.caption.bold()).foregroundStyle(RitmoTheme.workout)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Cerca esercizio")
        .navigationTitle("Esercizi")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - SelectableStatChart (tap or drag to read any point)
//
// One interactive chart for the whole Statistiche screen: tap/drag shows a
// dashed rule with the value + date of the nearest point. Bars dim except
// the selected one; the optional dashed reference line ("1RM gara") is
// included in the y-domain.

struct SelectableStatChart: View {
    let points: [DateValuePoint]
    var isBar = false
    var weekly = false                    // week buckets + week axis labels
    var barWidth: CGFloat = 12
    var xAxisWeekStride = 1
    var kiloYAxis = false
    var color: Color = RitmoTheme.accent
    var decimals = 0
    var unit = ""                         // appended in the selection bubble
    var yDomain: ClosedRange<Double>? = nil
    var reference: (label: String, value: Double)? = nil
    var height: CGFloat = 140

    @State private var selection: Date?

    private var selected: DateValuePoint? {
        guard let selection else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
    }

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        var values = points.map(\.value)
        if let reference { values.append(reference.value) }
        let hi = values.max() ?? 1
        if isBar { return 0...(max(hi, 1) * 1.15) }
        let lo = values.min() ?? 0
        let pad = max((hi - lo) * 0.15, 2)
        return max(lo - pad, 0)...(hi + pad)
    }

    var body: some View {
        Chart {
            if let reference {
                RuleMark(y: .value("Riferimento", reference.value))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.orange)
                    .annotation(position: .topTrailing) {
                        Text(LocalizedStringKey(reference.label))
                            .font(.caption2.bold()).foregroundStyle(.orange)
                    }
            }
            ForEach(points) { point in
                if isBar {
                    BarMark(x: .value("Data", point.date, unit: weekly ? .weekOfYear : .day),
                            y: .value("Valore", point.value),
                            width: .fixed(barWidth))
                        .foregroundStyle(color.gradient)
                        .cornerRadius(3)
                        .opacity(selected == nil || selected?.id == point.id ? 1 : 0.4)
                } else {
                    LineMark(x: .value("Data", point.date), y: .value("Valore", point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Data", point.date), y: .value("Valore", point.value))
                        .foregroundStyle(color)
                }
            }
            if let selected {
                RuleMark(x: .value("Selezione", selected.date, unit: weekly ? .weekOfYear : .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(String(format: "%.\(decimals)f", selected.value) + unit)
                                .font(.caption.bold()).foregroundStyle(color)
                            Text(selected.date, format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selection)
        .chartXAxis {
            if weekly {
                AxisMarks(values: .stride(by: .weekOfYear, count: xAxisWeekStride)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            } else {
                AxisMarks()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(kiloYAxis && v >= 1000 ? String(format: "%.0fk", v / 1000)
                                                    : String(format: "%.\(decimals)f", v))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Human label for an OpenPowerlifting event code (localization key).
func eventLabel(_ code: String) -> String {
    switch code {
    case "SBD": return "Gara completa"
    case "B":   return "Solo Panca"
    case "S":   return "Solo Squat"
    case "D":   return "Solo Stacco"
    case "BD":  return "Panca + Stacco"
    default:    return code
    }
}

// MARK: - RecordsTimelineView (chronology of all-time bests)

struct RecordsTimelineView: View {
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \RaceResult.date, order: .reverse) private var races: [RaceResult]
    @State private var events: [WorkoutStats.PREvent] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if events.isEmpty {
                Text("Nessun record ancora: i primati compaiono man mano che migliori.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(RitmoTheme.pagePadding)
            } else {
                List(events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: icon(for: event.kind))
                            .font(.caption)
                            .foregroundStyle(color(for: event.kind))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(event.name)).font(.subheadline.bold()).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(event.date, format: .dateTime.day().month(.abbreviated).year())
                                if let raceName = event.raceName {
                                    Text("· \(raceName)").lineLimit(1)
                                }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        valueView(for: event.kind)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Record")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !loaded else { return }
            events = WorkoutStats.prTimeline(sessions: sessions, races: races)
            loaded = true
        }
    }

    private func icon(for kind: WorkoutStats.PREventKind) -> String {
        switch kind {
        case .liftE1RM:       return "dumbbell.fill"
        case .racePB:         return "flag.checkered"
        case .sessionTonnage: return "scalemass.fill"
        }
    }

    private func color(for kind: WorkoutStats.PREventKind) -> Color {
        switch kind {
        case .liftE1RM:       return RitmoTheme.workout
        case .racePB:         return RitmoTheme.accent
        case .sessionTonnage: return .orange
        }
    }

    @ViewBuilder
    private func valueView(for kind: WorkoutStats.PREventKind) -> some View {
        switch kind {
        case .liftE1RM(let kg, let previous):
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f kg", kg)).font(.caption.bold())
                if let previous {
                    Text(String(format: "%+.1f", kg - previous))
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        case .racePB(let seconds, let previous):
            VStack(alignment: .trailing, spacing: 1) {
                Text(EnduranceStats.formatDuration(seconds)).font(.caption.bold())
                if let previous {
                    Text("−" + EnduranceStats.formatDuration(previous - seconds))
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        case .sessionTonnage(let kg, let previous):
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f kg", kg)).font(.caption.bold())
                if let previous {
                    Text(String(format: "%+.0f", kg - previous))
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - AttemptCalculatorView (meet attempts + warm-up ramp)

struct AttemptCalculatorView: View {
    let maxes: (squat: Double, bench: Double, deadlift: Double)
    @Environment(\.dismiss) private var dismiss

    @State private var liftIndex = 0
    @State private var maxText = ""

    private var prefill: Double {
        [maxes.squat, maxes.bench, maxes.deadlift][liftIndex]
    }
    private var oneRM: Double {
        Double(maxText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Everything plate-rounded to 2.5 kg — that's what exists on the bar.
    private func rounded(_ kg: Double) -> Double { MeetPlan.plateRounded(kg) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Alzata", selection: $liftIndex) {
                        Text("Squat").tag(0)
                        Text("Panca Piana").tag(1)
                        Text("Stacco da Terra").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: liftIndex) { _, _ in
                        if prefill > 0 { maxText = String(format: "%.4g", prefill) }
                    }
                    HStack {
                        Text("1RM")
                        Spacer()
                        TextField("—", text: $maxText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
                    }
                } footer: {
                    Text("Precompilato dal massimale gara (OpenPowerlifting o manuale); modificabile.")
                }

                if oneRM > 0 {
                    Section {
                        let attempts = MeetPlan.attempts(oneRM: oneRM)
                        attemptRow("1° tentativo", kg: attempts[0])
                        attemptRow("2° tentativo", kg: attempts[1])
                        attemptRow("3° tentativo", kg: attempts[2])
                    } header: { Text("Tentativi") } footer: {
                        Text(String(format: NSLocalizedString(
                            "Terzo tentativo al massimale, salti di %@ kg (4%%) sotto — arrotondati a 2,5 kg.",
                            comment: ""),
                            String(format: "%.4g", MeetPlan.attemptJump(oneRM: oneRM))))
                    }

                    Section {
                        warmupRow("Bilanciere", kg: MeetPlan.barKg, reps: 10)
                        ForEach(MeetPlan.warmups(oneRM: oneRM), id: \.kg) { set in
                            warmupRow("\(set.percentOfMax)%", kg: set.kg, reps: set.reps)
                        }
                    } header: { Text("Riscaldamento") } footer: {
                        Text("I salti si accorciano fino al primo tentativo: l'ultimo riscaldamento resta almeno un salto pieno sotto l'apertura.")
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Calcolatore gara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear {
                if maxText.isEmpty, prefill > 0 { maxText = String(format: "%.4g", prefill) }
            }
        }
    }

    private func attemptRow(_ label: String, kg: Double) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(.subheadline)
            Spacer()
            Text(String(format: "%.4g kg", kg))
                .font(.subheadline.bold()).foregroundStyle(RitmoTheme.workout)
        }
    }

    private func warmupRow(_ label: String, kg: Double, reps: Int) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(.caption)
            Spacer()
            Text(String(format: "%.4g kg × %d", kg, reps))
                .font(.caption.bold())
        }
    }
}

// MARK: - Keyboard dismissal (number pads have no return key)

extension View {
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    /// "Fine" button above the keyboard + drag-to-dismiss on the form.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { dismissKeyboard() }
                }
            }
    }
}

// MARK: - CalculatorsView (meet attempts · RPE · running pace)

struct CalculatorsView: View {
    @Query private var storedGoals: [UserGoals]
    @AppStorage("oplUsername") private var oplUsername = ""

    @State private var showingAttempts = false
    @State private var showingRPE = false
    @State private var showingPace = false
    @State private var showingHRPace = false
    @State private var compMaxes: (squat: Double, bench: Double, deadlift: Double) = (0, 0, 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RitmoTheme.gap) {
                calculatorRow(icon: "function", color: RitmoTheme.workout,
                              title: "Calcolatore gara",
                              subtitle: "Tentativi e riscaldamento dal massimale") {
                    showingAttempts = true
                }
                calculatorRow(icon: "gauge.with.needle", color: .orange,
                              title: "Calcolatore RPE",
                              subtitle: "e1RM e pesi target da peso × ripetizioni @ RPE") {
                    showingRPE = true
                }
                calculatorRow(icon: "figure.run", color: .mint,
                              title: "Calcolatore passo",
                              subtitle: "Passo, tempo e distanza per la corsa") {
                    showingPace = true
                }
                calculatorRow(icon: "heart.text.square", color: .pink,
                              title: "Passo previsto da FC",
                              subtitle: "Relazione passo–FC stimata dalle tue corse") {
                    showingHRPace = true
                }
            }
            .padding(RitmoTheme.pagePadding)
        }
        .navigationTitle("Calcolatori")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingAttempts) {
            AttemptCalculatorView(maxes: compMaxes)
        }
        .sheet(isPresented: $showingRPE) {
            RPECalculatorView()
        }
        .sheet(isPresented: $showingPace) {
            PaceCalculatorView()
        }
        .sheet(isPresented: $showingHRPace) {
            HRPaceCalculatorView()
        }
        .task {
            // Same priority as everywhere: OPL bests when connected, else the
            // manually entered maxes.
            let goals = storedGoals.first
            compMaxes = (goals?.compSquatKg ?? 0, goals?.compBenchKg ?? 0, goals?.compDeadliftKg ?? 0)
            if !oplUsername.isEmpty,
               let meets = try? await OpenPowerliftingService.fetchMeets(username: oplUsername),
               !meets.isEmpty {
                compMaxes = (meets.compactMap(\.bestSquatKg).max() ?? 0,
                             meets.compactMap(\.bestBenchKg).max() ?? 0,
                             meets.compactMap(\.bestDeadliftKg).max() ?? 0)
            }
        }
    }

    private func calculatorRow(icon: String, color: Color, title: String,
                               subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FitCard {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3).foregroundStyle(color)
                        .frame(width: 38, height: 38)
                        .background(color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(title)).font(.subheadline.bold())
                        Text(LocalizedStringKey(subtitle))
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PaceCalculatorView (pace · time · distance, any one from the other two)

struct PaceCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    enum Solve: CaseIterable {
        case time, pace, distance
        var label: String {
            switch self {
            case .time:     return "Tempo"
            case .pace:     return "Passo"
            case .distance: return "Distanza"
            }
        }
    }

    @State private var solve: Solve = .time
    @State private var distanceKmText = ""
    @State private var hoursText = ""
    @State private var minutesText = ""
    @State private var secondsText = ""
    @State private var paceMinText = ""
    @State private var paceSecText = ""

    private var distanceKm: Double {
        Double(distanceKmText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var timeSeconds: Int {
        (Int(hoursText) ?? 0) * 3600 + (Int(minutesText) ?? 0) * 60 + (Int(secondsText) ?? 0)
    }
    private var paceSecondsPerKm: Double {
        Double((Int(paceMinText) ?? 0) * 60 + (Int(paceSecText) ?? 0))
    }

    private var result: (value: String, detail: String)? {
        switch solve {
        case .time:
            guard distanceKm > 0, paceSecondsPerKm > 0 else { return nil }
            let seconds = Int((paceSecondsPerKm * distanceKm).rounded())
            return (EnduranceStats.formatDuration(seconds),
                    String(format: "%.2f km/h", 3600 / paceSecondsPerKm))
        case .pace:
            guard distanceKm > 0, timeSeconds > 0 else { return nil }
            let pace = Double(timeSeconds) / distanceKm
            return (EnduranceStats.formatPace(pace) + "/km",
                    String(format: "%.2f km/h", distanceKm / (Double(timeSeconds) / 3600)))
        case .distance:
            guard timeSeconds > 0, paceSecondsPerKm > 0 else { return nil }
            let km = Double(timeSeconds) / paceSecondsPerKm
            return (String(format: "%.2f km", km),
                    String(format: "%.2f km/h", 3600 / paceSecondsPerKm))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Calcola", selection: $solve) {
                        ForEach(Solve.allCases, id: \.self) { option in
                            Text(LocalizedStringKey(option.label)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if solve != .distance {
                    Section {
                        HStack {
                            TextField("0", text: $distanceKmText)
                                .keyboardType(.decimalPad)
                            Text("km").foregroundStyle(RitmoTheme.textSecondary)
                            Menu {
                                Button("5 km") { distanceKmText = "5" }
                                Button("10 km") { distanceKmText = "10" }
                                Button("Mezza maratona") { distanceKmText = "21,0975" }
                                Button("Maratona") { distanceKmText = "42,195" }
                            } label: {
                                Label("Distanze standard", systemImage: "list.bullet").font(.caption)
                            }
                        }
                    } header: { Text("Distanza") }
                }

                if solve != .time {
                    Section {
                        HStack(spacing: 8) {
                            TextField("0", text: $hoursText).keyboardType(.numberPad)
                            Text("h").foregroundStyle(RitmoTheme.textSecondary)
                            TextField("0", text: $minutesText).keyboardType(.numberPad)
                            Text("min").foregroundStyle(RitmoTheme.textSecondary)
                            TextField("0", text: $secondsText).keyboardType(.numberPad)
                            Text("s").foregroundStyle(RitmoTheme.textSecondary)
                        }
                    } header: { Text("Tempo") }
                }

                if solve != .pace {
                    Section {
                        HStack(spacing: 8) {
                            TextField("0", text: $paceMinText).keyboardType(.numberPad)
                            Text("min").foregroundStyle(RitmoTheme.textSecondary)
                            TextField("0", text: $paceSecText).keyboardType(.numberPad)
                            Text("s · /km").foregroundStyle(RitmoTheme.textSecondary)
                        }
                    } header: { Text("Passo") }
                }

                if let result {
                    Section {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(result.value)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.mint)
                            Spacer()
                            Text(result.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Risultato") }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Calcolatore passo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}

// MARK: - HRPaceCalculatorView (expected pace at a heart rate, from run history)

struct HRPaceCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]

    enum Solve: CaseIterable {
        case pace, hr
        var label: String {
            switch self {
            case .pace: return "Passo"
            case .hr:   return "FC"
            }
        }
    }

    @State private var solve: Solve = .pace
    @State private var hrText = ""
    @State private var paceMinText = ""
    @State private var paceSecText = ""
    @State private var model: EnduranceStats.PaceHRModel?
    @State private var runsWithHR = 0
    @State private var loading = true

    private var result: (value: String, detail: String, extrapolated: Bool)? {
        guard let model else { return nil }
        switch solve {
        case .pace:
            guard let hr = Double(hrText), hr > 0,
                  let pace = model.paceSecondsPerKm(atHR: hr) else { return nil }
            return (EnduranceStats.formatPace(pace) + "/km",
                    String(format: "%.2f km/h", 3600 / pace),
                    !model.hrRange.contains(hr))
        case .hr:
            let paceSec = Double((Int(paceMinText) ?? 0) * 60 + (Int(paceSecText) ?? 0))
            guard paceSec > 0, let hr = model.hr(atPaceSecondsPerKm: paceSec) else { return nil }
            return (String(format: "%.0f bpm", hr),
                    String(format: "%.2f km/h", 3600 / paceSec),
                    paceSec < model.paceRange.lowerBound || paceSec > model.paceRange.upperBound)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                } else if let model {
                    Section {
                        Picker("Calcola", selection: $solve) {
                            ForEach(Solve.allCases, id: \.self) { option in
                                Text(LocalizedStringKey(option.label)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if solve == .pace {
                        Section {
                            HStack {
                                TextField("0", text: $hrText).keyboardType(.numberPad)
                                Text("bpm").foregroundStyle(RitmoTheme.textSecondary)
                            }
                        } header: { Text("FC media") }
                    } else {
                        Section {
                            HStack(spacing: 8) {
                                TextField("0", text: $paceMinText).keyboardType(.numberPad)
                                Text("min").foregroundStyle(RitmoTheme.textSecondary)
                                TextField("0", text: $paceSecText).keyboardType(.numberPad)
                                Text("s · /km").foregroundStyle(RitmoTheme.textSecondary)
                            }
                        } header: { Text("Passo") }
                    }

                    if let result {
                        Section {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(result.value)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(.pink)
                                Spacer()
                                Text(result.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } header: { Text("Risultato") } footer: {
                            if result.extrapolated {
                                Text("Fuori dall'intervallo osservato: valore estrapolato.")
                            }
                        }
                    }

                    Section {
                    } footer: {
                        Text(String(format: NSLocalizedString(
                            "Basato su %@ corse negli ultimi 6 mesi · FC media osservata %@–%@ bpm",
                            comment: ""),
                            "\(model.runCount)",
                            "\(Int(model.hrRange.lowerBound))",
                            "\(Int(model.hrRange.upperBound))"))
                    }
                } else {
                    Section {
                        Text("Servono almeno 5 corse di 15+ minuti con dati di frequenza cardiaca negli ultimi 6 mesi.")
                            .font(.subheadline)
                        Text(String(format: NSLocalizedString("Corse trovate: %@", comment: ""),
                                    "\(runsWithHR)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Passo previsto da FC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .task {
                // Steady-ish runs only: 15+ min and 1+ km keep warm-up jogs and
                // paused GPS fragments out of the fit; 6 months keeps it current.
                let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .distantPast
                let runs = sessions.filter {
                    $0.hkActivityType == 37
                    && $0.startTime >= cutoff
                    && $0.distanceMeters > 1_000
                    && $0.endTime.timeIntervalSince($0.startTime) >= 900
                }.prefix(60)

                var points: [(hr: Double, speedMps: Double)] = []
                for run in runs {
                    guard let hr = await healthRepo.fetchAverageHeartRate(start: run.startTime,
                                                                          end: run.endTime)
                    else { continue }
                    let seconds = run.endTime.timeIntervalSince(run.startTime)
                    points.append((hr: hr, speedMps: run.distanceMeters / seconds))
                }
                runsWithHR = points.count
                model = EnduranceStats.paceHRModel(points: points)
                loading = false
            }
        }
    }
}

// MARK: - RPECalculatorView (e1RM + target weights from the RTS RPE chart)

struct RPECalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var reps = 5
    @State private var rpe = 8.0
    @State private var targetRepsSelection = 1   // 0 = nothing selected yet

    private static let rpeSteps: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    /// RTS rep-max percentages of the 1RM at RPE 10, for 1…10 reps. RPE below
    /// 10 shifts along the same column via reps-in-reserve (effective reps =
    /// reps + 10 − RPE), half steps interpolate, past 10 extrapolates.
    private static let rpe10Percents: [Double] = [100, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9]

    private func percentOf1RM(reps: Int, rpe: Double) -> Double {
        let effective = Double(reps) + (10 - rpe)
        func value(at index: Int) -> Double {
            if index < 0 { return 100 }
            if index < Self.rpe10Percents.count { return Self.rpe10Percents[index] }
            let last = Self.rpe10Percents.count - 1
            let slope = Self.rpe10Percents[last] - Self.rpe10Percents[last - 1]
            return Self.rpe10Percents[last] + slope * Double(index - last)
        }
        let lowerIndex = Int(floor(effective)) - 1     // 1 effective rep → index 0
        let fraction = effective - floor(effective)
        let lower = value(at: lowerIndex)
        let upper = value(at: lowerIndex + 1)
        return lower + (upper - lower) * fraction
    }

    private var weight: Double {
        Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var e1RM: Double {
        guard weight > 0 else { return 0 }
        return weight / (percentOf1RM(reps: reps, rpe: rpe) / 100)
    }
    private func plateRounded(_ kg: Double) -> Double { (kg / 2.5).rounded() * 2.5 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Peso sollevato")
                        Spacer()
                        TextField("—", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(RitmoTheme.textSecondary).font(.caption)
                    }
                    Stepper(value: $reps, in: 1...10) {
                        Text(String(format: NSLocalizedString("Ripetizioni: %@", comment: ""), "\(reps)"))
                    }
                    Picker("RPE", selection: $rpe) {
                        ForEach(Self.rpeSteps, id: \.self) { step in
                            Text(String(format: "%.1f", step)).tag(step)
                        }
                    }
                } header: { Text("Serie fatta") }

                if e1RM > 0 {
                    Section {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", e1RM))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(RitmoTheme.workout)
                            Text("kg · 1RM stimato").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Stepper(value: $targetRepsSelection, in: 0...12) {
                            Text(String(format: NSLocalizedString("Ripetizioni: %@", comment: ""),
                                        "\(targetRepsSelection)"))
                        }
                        if targetRepsSelection >= 1 {
                            // The whole RPE column for the chosen rep count,
                            // heaviest first: RPE → % of estimated 1RM → load.
                            ForEach(Self.rpeSteps.reversed(), id: \.self) { step in
                                let pct = percentOf1RM(reps: targetRepsSelection, rpe: step)
                                HStack {
                                    Text(String(format: "RPE %.1f", step)).font(.caption)
                                    Spacer()
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.4g kg", plateRounded(e1RM * pct / 100)))
                                        .font(.caption.bold())
                                        .frame(width: 80, alignment: .trailing)
                                }
                            }
                        }
                    } header: { Text("Ripetizioni target") } footer: {
                        Text("Tabella RPE RTS (Reactive Training Systems); oltre 10 ripetizioni effettive i valori sono estrapolati. Pesi arrotondati a 2,5 kg.")
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Calcolatore RPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}

// MARK: - RaceEditorView (manual race entry)

struct RaceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var sport: RaceSport = .run
    @State private var name = ""
    @State private var date = Date.now
    @State private var distanceKmText = ""
    @State private var hoursText = ""
    @State private var minutesText = ""
    @State private var secondsText = ""

    private var distanceMeters: Double {
        (Double(distanceKmText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 1000
    }
    private var totalSeconds: Int {
        (Int(hoursText) ?? 0) * 3600 + (Int(minutesText) ?? 0) * 60 + (Int(secondsText) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(RaceSport.allCases, id: \.self) { s in
                            Text(LocalizedStringKey(s.displayName)).tag(s)
                        }
                    }
                    TextField("Nome gara", text: $name)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                } header: { Text("Gara") }

                Section {
                    HStack {
                        TextField("0", text: $distanceKmText)
                            .keyboardType(.decimalPad)
                        Text("km").foregroundStyle(RitmoTheme.textSecondary)
                        Menu {
                            ForEach(presets, id: \.label) { preset in
                                Button(preset.label) {
                                    distanceKmText = String(format: "%.4g", preset.meters / 1000)
                                }
                            }
                        } label: {
                            Label("Distanze standard", systemImage: "list.bullet")
                                .font(.caption)
                        }
                    }
                } header: { Text("Distanza") }

                Section {
                    HStack(spacing: 8) {
                        TextField("0", text: $hoursText).keyboardType(.numberPad)
                        Text("h").foregroundStyle(RitmoTheme.textSecondary)
                        TextField("0", text: $minutesText).keyboardType(.numberPad)
                        Text("min").foregroundStyle(RitmoTheme.textSecondary)
                        TextField("0", text: $secondsText).keyboardType(.numberPad)
                        Text("s").foregroundStyle(RitmoTheme.textSecondary)
                    }
                } header: { Text("Tempo ufficiale") }
            }
            .keyboardDoneButton()
            .navigationTitle("Nuova gara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(distanceMeters <= 0 || totalSeconds <= 0)
                }
            }
        }
    }

    private var presets: [(label: String, meters: Double)] {
        switch sport {
        case .run:
            return [("5 km", 5_000), ("10 km", 10_000),
                    ("Mezza maratona", 21_097.5), ("Maratona", 42_195)]
        case .ride:
            return [("25 km", 25_000), ("50 km", 50_000), ("100 km", 100_000)]
        case .swim:
            return [("1,5 km", 1_500), ("1,9 km", 1_900), ("3,8 km", 3_800)]
        case .triathlon:
            return [("Sprint", 25_750), ("Olimpico", 51_500),
                    ("70.3", 113_000), ("Ironman", 226_000)]
        case .other:
            return []
        }
    }

    private func save() {
        modelContext.insert(RaceResult(date: date,
                                       name: name.trimmingCharacters(in: .whitespaces),
                                       sport: sport,
                                       distanceMeters: distanceMeters,
                                       durationSeconds: totalSeconds))
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - RaceListView (full race log, deletable)

struct RaceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RaceResult.date, order: .reverse) private var races: [RaceResult]

    var body: some View {
        List {
            ForEach(races) { race in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: race.sport.sfSymbol)
                            .font(.caption).foregroundStyle(RitmoTheme.accent)
                        Text(race.name.isEmpty ? race.sport.displayName : race.name)
                            .font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        Text(EnduranceStats.formatDuration(race.durationSeconds))
                            .font(.caption.bold())
                    }
                    HStack {
                        Text("\(race.date, format: .dateTime.day().month(.abbreviated).year()) · \(String(format: "%.4g", race.distanceMeters / 1000)) km")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if race.sourceRaw == "strava" {
                            Text("Strava").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(races[index]) }
                try? modelContext.save()
            }
        }
        .navigationTitle("Gare")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - OPLMeetsView (full competition history)

struct OPLMeetsView: View {
    let meets: [OPLMeet]
    let username: String

    var body: some View {
        List(meets) { meet in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(meet.meetName).font(.subheadline.bold()).lineLimit(2)
                    Spacer()
                    if !meet.place.isEmpty {
                        Text(String(format: NSLocalizedString("%@°", comment: ""), meet.place))
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RitmoTheme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(RitmoTheme.accent)
                    }
                }
                HStack(spacing: 4) {
                    Text(meet.date, format: .dateTime.day().month(.abbreviated).year())
                    Text("· \(meet.federation) · \(meet.equipment) ·")
                    Text(LocalizedStringKey(eventLabel(meet.event)))
                }
                .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    // Sport-universal abbreviations — deliberately unlocalized.
                    liftValue("SQ", meet.bestSquatKg)
                    liftValue("BP", meet.bestBenchKg)
                    liftValue("DL", meet.bestDeadliftKg)
                    Spacer()
                    if let total = meet.totalKg {
                        Text("Tot \(fmt(total))").font(.caption.bold())
                    }
                    if let gl = meet.goodlift {
                        Text(String(format: "%.1f GL", gl))
                            .font(.caption.bold()).foregroundStyle(RitmoTheme.accent)
                    }
                }
                if let bw = meet.bodyweightKg {
                    Text(String(format: NSLocalizedString("Peso gara: %@ kg (classe %@)", comment: ""),
                                fmt(bw), meet.weightClass))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle(username)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func liftValue(_ prefix: String, _ kg: Double?) -> some View {
        Text("\(prefix) \(kg.map(fmt) ?? "—")")
            .font(.caption)
            .foregroundStyle(kg != nil ? Color.primary : .secondary)
    }

    private func fmt(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }
}

// MARK: - ExerciseProgressionView (one exercise over time)

struct ExerciseProgressionView: View {
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var storedGoals: [UserGoals]
    let exerciseName: String

    @State private var progression: [ExerciseDataPoint] = []
    @State private var volumeHistory: [DateValuePoint] = []
    @State private var record: PersonalRecord?
    @State private var compReference: Double?
    @State private var loaded = false
    @AppStorage("oplUsername") private var oplUsername = ""

    var body: some View {
        ScrollView {
            if loaded {
                VStack(alignment: .leading, spacing: RitmoTheme.gap) {

                    // Headline numbers
                    FitCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 0) {
                                if let record {
                                    StatItem(value: String(format: "%.0f", record.estimatedOneRepMax),
                                             label: "1RM stimato", icon: "trophy")
                                    Divider().frame(height: 40)
                                    StatItem(value: "\(fmtWeight(record.weightKg))×\(record.reps)",
                                             label: "miglior serie", icon: "scalemass")
                                    Divider().frame(height: 40)
                                }
                                StatItem(value: "\(progression.count)", label: "sessioni", icon: "calendar")
                            }
                            // Estimate vs real comp max, when both exist.
                            if let compReference, let record, compReference > 0 {
                                let delta = record.estimatedOneRepMax - compReference
                                Divider()
                                HStack {
                                    Text("Differenza stima − gara")
                                        .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                                    Spacer()
                                    Text(String(format: "%+.1f kg (%+.0f%%) · ", delta,
                                                delta / compReference * 100)
                                         + String(format: NSLocalizedString("gara %@ kg", comment: ""),
                                                  fmtWeight(compReference)))
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    if progression.count >= 2 {
                        chartCard(title: "1RM stimato (Epley)",
                                  subtitle: "Migliore stima per sessione",
                                  points: progression.map { DateValuePoint(date: $0.date, value: $0.estimatedOneRepMax) },
                                  color: RitmoTheme.accent,
                                  reference: compReference)
                        chartCard(title: "Peso della serie migliore",
                                  subtitle: "Serie più pesante per sessione",
                                  points: progression.map { DateValuePoint(date: $0.date, value: $0.weightKg) },
                                  color: RitmoTheme.workout)
                    }
                    if volumeHistory.count >= 2 {
                        volumeCard
                    }
                    if progression.count < 2 {
                        FitCard {
                            Text("Servono almeno due sessioni con questo esercizio per la progressione")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(RitmoTheme.pagePadding)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .navigationTitle(exerciseName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !loaded else { return }
            let service = PRService()
            progression = service.progression(for: exerciseName, in: sessions)
            volumeHistory = WorkoutStats.volumeHistory(for: exerciseName, in: sessions)
            record = service.calculateAllPRs(from: sessions)[exerciseName]
            loaded = true

            // "1RM gara" reference: OpenPowerlifting's best meet lift when
            // connected, the manually entered max otherwise.
            guard let lift = WorkoutStats.SBDLift.classify(exerciseName) else { return }
            compReference = storedGoals.first?.compMax(for: lift)
            if !oplUsername.isEmpty,
               let meets = try? await OpenPowerliftingService.fetchMeets(username: oplUsername) {
                let best: Double?
                switch lift {
                case .squat:    best = meets.compactMap(\.bestSquatKg).max()
                case .bench:    best = meets.compactMap(\.bestBenchKg).max()
                case .deadlift: best = meets.compactMap(\.bestDeadliftKg).max()
                }
                if let best { compReference = best }
            }
        }
    }

    private func chartCard(title: String, subtitle: LocalizedStringKey,
                           points: [DateValuePoint], color: Color,
                           reference: Double? = nil) -> some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                SelectableStatChart(points: points, color: color, decimals: 1, unit: " kg",
                                    reference: reference.map { ("1RM gara", $0) })
            }
        }
    }

    private var volumeCard: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Volume per sessione")
                Text("peso × ripetizioni, tutte le serie dell'esercizio")
                    .font(.caption2).foregroundStyle(.secondary)
                SelectableStatChart(points: volumeHistory, isBar: true, barWidth: 8,
                                    kiloYAxis: true, color: RitmoTheme.workout,
                                    unit: " kg", height: 130)
            }
        }
    }

    private func fmtWeight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }
}
