import SwiftUI
import SwiftData
import HealthKit
import MapKit
import CoreLocation
import Charts
import RitmoCore

struct RouteSegment: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let zone: Int  // 0 = no HR data, 1–5 = HR zones

    var color: Color {
        switch zone {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }
    var label: String { zone > 0 ? "Z\(zone)" : "--" }
}

private func buildRouteSegments(locations: [CLLocation], hrSamples: [HRSample], maxHR: Double) -> [RouteSegment] {
    guard !locations.isEmpty else { return [] }

    let zones: [Int] = locations.map { loc in
        guard !hrSamples.isEmpty else { return 0 }
        let t = loc.timestamp
        let closest = hrSamples.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }!
        let pct = closest.bpm / maxHR
        if pct < 0.60 { return 1 }
        if pct < 0.70 { return 2 }
        if pct < 0.80 { return 3 }
        if pct < 0.90 { return 4 }
        return 5
    }

    var segments: [RouteSegment] = []
    var i = 0
    while i < locations.count {
        let zone = zones[i]
        var coords = [locations[i].coordinate]
        var j = i + 1
        while j < locations.count && zones[j] == zone { coords.append(locations[j].coordinate); j += 1 }
        if j < locations.count { coords.append(locations[j].coordinate) }
        segments.append(RouteSegment(coordinates: coords, zone: zone))
        i = j
    }
    return segments
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var allSessions: [WorkoutSession]
    let session: WorkoutSession

    @State private var hrData: WorkoutHeartRateData?
    @State private var routeLocations: [CLLocation] = []
    @State private var routeSegments: [RouteSegment] = []
    @State private var weekLoad: TrainingLoad?
    @State private var hrRecovery: Int?
    @State private var observedMaxHR: Double?
    @State private var isLoadingHR = false
    @State private var showingRPEInfo = false
    @State private var showingDeleteDialog = false
    @State private var showingEditor = false
    @Environment(\.dismiss) private var dismiss

    /// Sets grouped by exercise, in first-appearance order (single pass).
    var setsByExercise: [(String, [WorkoutSet])] {
        var order: [String] = []
        var groups: [String: [WorkoutSet]] = [:]
        for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            let name = set.exercise?.name ?? "Esercizio"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(set)
        }
        return order.map { ($0, groups[$0]!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RitmoTheme.gap) {

                // MARK: Header stats
                FitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            let symbol = HKWorkoutActivityType(rawValue: UInt(session.hkActivityType))?.ritmoActivitySymbol ?? "dumbbell"
                            Image(systemName: symbol).font(.title2)
                                .foregroundStyle(session.source == .healthKit ? .red : RitmoTheme.workout)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(session.title)).font(.headline)
                                Text(session.startTime, format: .dateTime.weekday(.wide).day().month().year())
                                    .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                            }
                            Spacer()
                            SourceBadge(source: session.source)
                        }
                        Divider()
                        HStack(spacing: 0) {
                            StatItem(value: "\(session.durationMinutes)", label: "minuti", icon: "clock")
                            Divider().frame(height: 40)
                            StatItem(value: "\(session.effortScore)", label: "sforzo /10", icon: "gauge.with.dots.needle.50percent")
                            if session.activeCalories > 0 {
                                Divider().frame(height: 40)
                                StatItem(value: "\(Int(session.activeCalories))", label: "kcal attive", icon: "bolt.fill")
                            }
                            if session.distanceMeters > 100 {
                                Divider().frame(height: 40)
                                let (dist, unit) = session.distanceMeters >= 1000
                                    ? (String(format: "%.2f", session.distanceMeters / 1000), "km")
                                    : (String(format: "%.0f", session.distanceMeters), "m")
                                StatItem(value: dist, label: LocalizedStringKey(unit), icon: "arrow.forward")
                            }
                            if session.sets.count > 0 {
                                Divider().frame(height: 40)
                                StatItem(value: "\(session.sets.count)", label: "serie", icon: "list.bullet")
                            }
                        }
                    }
                }

                // MARK: Training load context — this workout vs the 7-day total
                workoutLoadCard

                // MARK: Set metrics (sets from Hevy or manual logging)
                if !session.sets.isEmpty {
                    setMetricsCard
                }

                // MARK: RPE (perceived effort)
                rpeCard

                // MARK: Heart Rate (Apple Health workouts)
                if session.source == .healthKit {
                    if isLoadingHR {
                        FitCard { ProgressView("Caricamento dati cardiaci…").frame(maxWidth: .infinity) }
                    } else if let hr = hrData {
                        // HR Summary
                        FitCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Frequenza cardiaca")
                                HStack(spacing: 0) {
                                    HeartStatItem(value: "\(Int(hr.avgBPM))", label: "media", color: .red)
                                    HeartStatItem(value: "\(Int(hr.maxBPM))", label: "massima", color: .orange)
                                    HeartStatItem(value: "\(Int(hr.minBPM))", label: "minima", color: .blue)
                                    if let hrRecovery {
                                        HeartStatItem(value: "−\(hrRecovery)", label: "recupero 1′", color: .green)
                                    }
                                }

                                if !hr.samples.isEmpty {
                                    let maxPts = 60
                                    let stride = max(1, hr.samples.count / maxPts)
                                    let downsampled = Swift.stride(from: 0, to: hr.samples.count, by: stride).map { i -> ChartPoint in
                                        let bucket = hr.samples[i..<min(i + stride, hr.samples.count)]
                                        let avg = bucket.map(\.bpm).reduce(0, +) / Double(bucket.count)
                                        return ChartPoint(date: bucket[bucket.startIndex].date, value: avg)
                                    }
                                    let lo = max(30, hr.minBPM - 10)
                                    let hi = min(220, hr.maxBPM + 10)
                                    InteractiveDateChart(
                                        title: "FC durante allenamento",
                                        points: downsampled,
                                        goal: nil,
                                        color: .red,
                                        unit: "bpm",
                                        chartUnit: .minute,
                                        chartType: .line,
                                        yDomain: lo...hi
                                    )
                                }
                            }
                        }

                        // HR Zones
                        if hr.zones.total > 0 {
                            FitCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Zone di frequenza cardiaca")
                                    Text(String(format: NSLocalizedString("Basate sulla tua FC max osservata: %@ bpm", comment: ""),
                                                "\(Int(observedMaxHR ?? 190))"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HRZonesChart(zones: hr.zones)
                                }
                            }
                        }
                    }

                    // MARK: Map (GPS workouts — colored by HR zone)
                    if !routeSegments.isEmpty {
                        FitCard {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: "Percorso")
                                Map {
                                    ForEach(routeSegments) { seg in
                                        MapPolyline(coordinates: seg.coordinates)
                                            .stroke(seg.color, lineWidth: 4)
                                    }
                                    if let first = routeSegments.first?.coordinates.first {
                                        Annotation("", coordinate: first) {
                                            Image(systemName: "circle.fill")
                                                .foregroundStyle(.green).font(.caption)
                                        }
                                    }
                                    if let last = routeSegments.last?.coordinates.last {
                                        Annotation("", coordinate: last) {
                                            Image(systemName: "flag.fill")
                                                .foregroundStyle(.red).font(.caption)
                                        }
                                    }
                                }
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                let hasZones = routeSegments.contains { $0.zone > 0 }
                                if hasZones {
                                    HStack(spacing: 14) {
                                        ForEach([1,2,3,4,5], id: \.self) { z in
                                            if routeSegments.contains(where: { $0.zone == z }) {
                                                HStack(spacing: 4) {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(RouteSegment(coordinates: [], zone: z).color)
                                                        .frame(width: 16, height: 4)
                                                    Text("Z\(z)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                }

                                Text(String(format: "%.2f km · %d punti GPS",
                                     session.distanceMeters / 1000, routeLocations.count))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: Exercise sets
                ForEach(setsByExercise, id: \.0) { exerciseName, sets in
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(exerciseName).font(.subheadline.bold())
                                Spacer()
                                if let group = sets.first?.exercise?.muscleGroup {
                                    Text(LocalizedStringKey(group.rawValue))
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(RitmoTheme.workout.opacity(0.12), in: Capsule())
                                        .foregroundStyle(RitmoTheme.workout)
                                }
                            }
                            HStack {
                                Text("Serie").frame(width: 40, alignment: .leading)
                                Text("Tipo").frame(width: 80, alignment: .leading)
                                Text("Peso").frame(maxWidth: .infinity, alignment: .center)
                                Text("Reps").frame(width: 50, alignment: .trailing)
                            }
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                            Divider()
                            ForEach(sets) { set in
                                HStack {
                                    Text("#\(set.setIndex + 1)")
                                        .frame(width: 40, alignment: .leading)
                                        .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                                    Text(LocalizedStringKey(set.setType.displayName))
                                        .frame(width: 80, alignment: .leading)
                                        .font(.caption).foregroundStyle(setTypeColor(set.setType))
                                    Text(String(format: "%.1f kg", set.weightKg))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .font(.subheadline.bold())
                                    Text(set.reps.map { "\($0)" } ?? "--")
                                        .frame(width: 50, alignment: .trailing)
                                        .font(.subheadline)
                                }
                                if set.setIndex < sets.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(RitmoTheme.pagePadding)
        }
        .navigationTitle(LocalizedStringKey(session.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if session.source == .manual {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) { showingDeleteDialog = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ManualWorkoutLogView(existing: session, onSaved: {
                GoalsSyncService.shared.sendTrainingLoad(recomputingFrom: modelContext)
            })
        }
        .confirmationDialog("Eliminare l'allenamento?", isPresented: $showingDeleteDialog) {
            if session.source == .manual {
                Button("Elimina allenamento", role: .destructive) { remove(alsoFromHealth: true) }
            } else if session.source == .hevy {
                Button("Elimina allenamento", role: .destructive) { remove(alsoFromHealth: false) }
            } else {
                Button("Rimuovi solo dall'app", role: .destructive) { remove(alsoFromHealth: false) }
                Button("Elimina anche da Apple Salute", role: .destructive) { remove(alsoFromHealth: true) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            if session.source == .manual {
                Text("L'allenamento verrà eliminato anche da Apple Salute.")
            } else if session.source == .hevy {
                Text("L'allenamento importato da Hevy verrà rimosso dall'app.")
            } else {
                Text("«Solo dall'app» lo nasconde ma resta in Apple Salute. «Elimina anche da Apple Salute» funziona solo per allenamenti creati da Ritmo.")
            }
        }
        .task {
            weekLoad = TrainingLoad.compute(from: allSessions)
            guard session.source == .healthKit else { return }
            isLoadingHR = true
            // The user's own observed max HR personalizes the zones; the old
            // fixed 190 stays only as fallback when no data exists.
            let maxHR = await healthRepo.fetchMaxHeartRate() ?? 190
            observedMaxHR = maxHR
            async let hr = healthRepo.fetchWorkoutHeartRate(start: session.startTime,
                                                            end: session.endTime, maxHR: maxHR)
            async let locs = healthRepo.fetchWorkoutRoute(start: session.startTime, end: session.endTime)
            async let recovery = healthRepo.fetchHeartRateRecovery(workoutEnd: session.endTime)
            let (fetchedHR, fetchedLocs) = await (hr, locs)
            hrRecovery = await recovery
            hrData = fetchedHR
            routeLocations = fetchedLocs
            if let hr = fetchedHR, !fetchedLocs.isEmpty {
                routeSegments = buildRouteSegments(locations: fetchedLocs, hrSamples: hr.samples, maxHR: maxHR)
            } else if !fetchedLocs.isEmpty {
                routeSegments = [RouteSegment(coordinates: fetchedLocs.map(\.coordinate), zone: 0)]
            }
            isLoadingHR = false
        }
    }

    // MARK: - Set metrics (volume, best set, e1RM… — numbers only sets can give)

    private struct SetMetrics {
        var totalVolume = 0.0                 // kg × reps over all sets
        var totalReps = 0
        var workingSets = 0                   // non-warmup
        var warmupSets = 0
        var bestSet: (name: String, weightKg: Double, reps: Int)?
        var bestE1RM: (name: String, kg: Double)?
        var avgSetRPE: Double?
        var groupShares: [(group: MuscleGroup, share: Double)] = []
    }

    private var setMetrics: SetMetrics {
        var m = SetMetrics()
        var rpeSum = 0.0, rpeCount = 0
        var groupVolume: [MuscleGroup: Double] = [:]
        for set in session.sets {
            let reps = set.reps ?? 0
            let volume = set.weightKg * Double(reps)
            m.totalVolume += volume
            m.totalReps += reps
            if set.setType == .warmup { m.warmupSets += 1 } else { m.workingSets += 1 }
            if let rpe = set.rpe { rpeSum += rpe; rpeCount += 1 }
            if volume > 0, let group = set.exercise?.muscleGroup {
                groupVolume[group, default: 0] += volume
            }
            guard set.setType != .warmup, set.weightKg > 0, reps > 0 else { continue }
            let name = set.exercise?.name ?? ""
            if set.weightKg > (m.bestSet?.weightKg ?? 0) {
                m.bestSet = (name, set.weightKg, reps)
            }
            // Epley loses meaning past ~12 reps, so those sets don't compete.
            if reps <= 12 {
                let e1rm = set.weightKg * (1 + Double(reps) / 30.0)
                if e1rm > (m.bestE1RM?.kg ?? 0) { m.bestE1RM = (name, e1rm) }
            }
        }
        if rpeCount > 0 { m.avgSetRPE = rpeSum / Double(rpeCount) }
        let totalGroupVolume = max(groupVolume.values.reduce(0, +), 1)
        m.groupShares = groupVolume.map { ($0.key, $0.value / totalGroupVolume) }
            .sorted { $0.share > $1.share }
        return m
    }

    private var setMetricsCard: some View {
        let m = setMetrics
        return FitCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Statistiche serie")
                HStack(spacing: 0) {
                    if m.totalVolume > 0 {
                        StatItem(value: volumeText(m.totalVolume), label: "volume (kg)", icon: "scalemass")
                    }
                    if m.totalReps > 0 {
                        if m.totalVolume > 0 { Divider().frame(height: 40) }
                        StatItem(value: "\(m.totalReps)", label: "ripetizioni", icon: "repeat")
                    }
                    if m.warmupSets > 0 {
                        Divider().frame(height: 40)
                        StatItem(value: "\(m.workingSets)", label: "serie effettive", icon: "flame.fill")
                    }
                    if let e1rm = m.bestE1RM {
                        Divider().frame(height: 40)
                        StatItem(value: String(format: "%.0f", e1rm.kg), label: "1RM stimato", icon: "trophy")
                    }
                }
                if let best = m.bestSet {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Miglior serie").font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(fmtKg(best.weightKg)) kg × \(best.reps)").font(.subheadline.bold())
                            Text(best.name).font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                        }
                    }
                }
                if let rpe = m.avgSetRPE {
                    HStack {
                        Text("RPE medio serie").font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f", rpe)).font(.subheadline.bold())
                    }
                }
                if m.groupShares.count > 1 {
                    Divider()
                    Text("Volume per gruppo muscolare").font(.caption).foregroundStyle(RitmoTheme.textSecondary)
                    ForEach(m.groupShares.prefix(4), id: \.group) { item in
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(item.group.rawValue))
                                .font(.caption2)
                                .frame(width: 92, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(muscleColor(item.group).opacity(0.15)).frame(height: 6)
                                    Capsule().fill(muscleColor(item.group))
                                        .frame(width: geo.size.width * CGFloat(item.share), height: 6)
                                }
                            }
                            .frame(height: 6)
                            Text("\(Int((item.share * 100).rounded()))%")
                                .font(.caption2.bold())
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(muscleColor(item.group))
                        }
                    }
                }
            }
        }
    }

    private func volumeText(_ kg: Double) -> String {
        kg >= 1000 ? String(format: "%.1fk", kg / 1000) : "\(Int(kg.rounded()))"
    }

    private func fmtKg(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    // MARK: - Training load (this workout vs the 7-day total)

    // TrainingLoad.compute walks every stored session — computed once per
    // appearance (.task) instead of on every body evaluation.
    @ViewBuilder
    private var workoutLoadCard: some View {
        if let total = weekLoad { loadContextCard(total) }
    }

    private func loadContextCard(_ total: TrainingLoad) -> some View {
        let thisLoad = session.loadValue
        let weekShare = total.acute > 0 ? min(thisLoad / Double(total.acute), 1.0) : 0
        let matched = total.matchedAverageLoad(for: session)
        let avgLoad = matched.value
        let vsAveragePct = avgLoad > 0 ? ((thisLoad - avgLoad) / avgLoad) * 100 : 0
        // Composed at runtime → localized explicitly (an interpolated
        // LocalizedStringKey would produce a key that matches no table entry).
        let avgLabel = matched.matchedCategory.map {
            String(format: NSLocalizedString("Media dei tuoi allenamenti di %@", comment: ""),
                   NSLocalizedString($0.displayName, comment: ""))
        } ?? NSLocalizedString("Media dei tuoi allenamenti", comment: "")
        let color = loadStatusColor(total.status)
        let vsAvgColor: Color = vsAveragePct > 10 ? .orange : (vsAveragePct < -10 ? .blue : .secondary)

        return NavigationLink {
            TrainingLoadDetailView(sessions: allSessions)
        } label: {
            FitCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        SectionHeader(title: "Carico di questo allenamento")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Int(thisLoad.rounded()))")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        Text("punteggio").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("su \(total.acute) (7gg)").font(.caption2).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.15)).frame(height: 8)
                            Capsule().fill(color).frame(width: geo.size.width * CGFloat(weekShare), height: 8)
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: NSLocalizedString("%@ del carico degli ultimi 7 giorni", comment: ""),
                                "\(Int((weekShare * 100).rounded()))%"))
                        .font(.caption2).foregroundStyle(.secondary)

                    if avgLoad > 0 {
                        Divider()
                        HStack {
                            Text(avgLabel)
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(vsAveragePct >= 0 ? "+\(Int(vsAveragePct.rounded()))%" : "\(Int(vsAveragePct.rounded()))%")
                                .font(.caption.bold())
                                .foregroundStyle(vsAvgColor)
                        }
                        Text("La tua media è \(Int(avgLoad.rounded())) punti per allenamento")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - RPE editor

    private var rpeCard: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SectionHeader(title: "Sforzo percepito (RPE)")
                    Button { showingRPEInfo = true } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(session.hasUserRPE ? "Impostato" : "Stima \(session.autoEffort)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(1...10, id: \.self) { v in
                        let selected = session.effortScore == v
                        Button {
                            setRPE((session.userRPE == v) ? nil : v)
                        } label: {
                            Text("\(v)")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity).frame(height: 30)
                                .background(selected ? rpeColor(v) : Color(.systemGray6),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if session.hasUserRPE {
                    Button("Usa stima automatica") { setRPE(nil) }
                        .font(.caption).foregroundStyle(RitmoTheme.accent)
                }
            }
        }
        .alert("Cos'è l'RPE?", isPresented: $showingRPEInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("RPE (Rate of Perceived Exertion) misura quanto è stato intenso l'allenamento, da 1 (molto facile) a 10 (sforzo massimo). Impostalo per rendere il carico più accurato — utile per la forza, dove la frequenza cardiaca resta bassa pur con alta intensità.")
        }
    }

    private func rpeColor(_ v: Int) -> Color {
        // Intensity: 1 = green (easy) → 10 = red (maximal).
        Color(hue: 0.33 * (1 - Double(v - 1) / 9), saturation: 0.8, brightness: 0.85)
    }

    /// Updates the local RPE and mirrors it to Apple Health (so it counts toward
    /// load on every device and appears in the Fitness app).
    private func setRPE(_ value: Int?) {
        session.userRPE = value
        try? modelContext.save()
        weekLoad = TrainingLoad.compute(from: allSessions)   // card shows live numbers
        GoalsSyncService.shared.sendTrainingLoad(recomputingFrom: modelContext)
        guard let uuid = session.hkWorkoutUUID else { return }
        Task {
            if let v = value {
                await healthRepo.saveWorkoutEffort(rpe: v, forWorkoutUUID: uuid)
            } else {
                await healthRepo.removeWorkoutEffort(forWorkoutUUID: uuid)
            }
        }
    }

    private func remove(alsoFromHealth: Bool) {
        let uuid = session.hkWorkoutUUID
        // App-authored workouts always take their HealthKit record with them.
        let deleteFromHealth = alsoFromHealth || session.source == .manual
        healthRepo.deleteWorkout(session, in: modelContext)   // exclude + local delete
        GoalsSyncService.shared.sendExcludedWorkouts(Array(HealthKitRepository.excludedWorkoutUUIDs()))
        GoalsSyncService.shared.sendTrainingLoad(recomputingFrom: modelContext)
        if deleteFromHealth, let uuid {
            Task { _ = await healthRepo.deleteHealthKitWorkout(uuid: uuid) }
        }
        dismiss()
    }
}
