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

    var body: some View {
        ScrollView {
            if let stats {
                VStack(alignment: .leading, spacing: RitmoTheme.gap) {
                    Picker("Sezione", selection: $section) {
                        Text("Palestra").tag(StatsSection.gym)
                        Text("Cardio").tag(StatsSection.cardio)
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .gym:
                        weeklySetsCard(stats)
                        tonnageCard(stats)
                        repRangeCard(stats)
                        frequencyCard(stats)
                        densityCard(stats)
                        relativeStrengthCard(stats)
                        compMaxCard(stats)
                        oplCard
                        exercisesCard(stats)
                    case .cardio:
                        pbCard(stats, sport: .run)
                        pbCard(stats, sport: .ride)
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
            setsForFilter = s.weeklySetsAll
            stats = s
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
