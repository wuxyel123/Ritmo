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
    @State private var isLoadingHR = false
    @State private var showingRPEInfo = false
    @State private var showingDeleteDialog = false
    @State private var showingEditor = false
    @Environment(\.dismiss) private var dismiss

    var setsByExercise: [(String, [WorkoutSet])] {
        var groups: [(String, [WorkoutSet])] = []
        var seen: [String] = []
        for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            let name = set.exercise?.name ?? "Esercizio"
            if !seen.contains(name) {
                seen.append(name)
                groups.append((name, session.sets.filter { $0.exercise?.name == name }
                    .sorted { $0.setIndex < $1.setIndex }))
            }
        }
        return groups
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
                                    Text("Basate su FC max stimata 190 bpm")
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
                                Text(sets.first?.exercise?.muscleGroup.sfSymbol ?? "dumbbell")
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
            ManualWorkoutLogView(existing: session, onSaved: { pushTrainingLoad() })
        }
        .confirmationDialog("Eliminare l'allenamento?", isPresented: $showingDeleteDialog) {
            Button("Rimuovi solo dall'app", role: .destructive) { remove(alsoFromHealth: false) }
            Button("Elimina anche da Apple Salute", role: .destructive) { remove(alsoFromHealth: true) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("«Solo dall'app» lo nasconde ma resta in Apple Salute. «Elimina anche da Apple Salute» funziona solo per allenamenti creati da Ritmo.")
        }
        .task {
            guard session.source == .healthKit else { return }
            isLoadingHR = true
            async let hr = healthRepo.fetchWorkoutHeartRate(start: session.startTime, end: session.endTime)
            async let locs = healthRepo.fetchWorkoutRoute(start: session.startTime, end: session.endTime)
            let (fetchedHR, fetchedLocs) = await (hr, locs)
            hrData = fetchedHR
            routeLocations = fetchedLocs
            if let hr = fetchedHR, !fetchedLocs.isEmpty {
                routeSegments = buildRouteSegments(locations: fetchedLocs, hrSamples: hr.samples, maxHR: 190)
            } else if !fetchedLocs.isEmpty {
                routeSegments = [RouteSegment(coordinates: fetchedLocs.map(\.coordinate), zone: 0)]
            }
            isLoadingHR = false
        }
    }

    private func setTypeColor(_ type: SetType) -> Color {
        switch type {
        case .normal: return RitmoTheme.textSecondary
        case .warmup: return .blue
        case .dropSet: return .orange
        case .failure: return .red
        }
    }

    // MARK: - Training load (this workout vs the 7-day total)

    private var workoutLoadCard: some View {
        let total = TrainingLoad.compute(from: allSessions)
        let thisLoad = session.loadValue
        let weekShare = total.acute > 0 ? min(thisLoad / Double(total.acute), 1.0) : 0
        let matched = total.matchedAverageLoad(for: session)
        let avgLoad = matched.value
        let vsAveragePct = avgLoad > 0 ? ((thisLoad - avgLoad) / avgLoad) * 100 : 0
        let avgLabel = matched.matchedCategory.map { "Media dei tuoi allenamenti di \($0.displayName)" }
            ?? "Media dei tuoi allenamenti"
        let color: Color = switch total.status {
            case .low:      .blue
            case .optimal:  .green
            case .high:     .orange
            case .veryHigh: .red
        }
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
                    Text("\(Int((weekShare * 100).rounded()))% del carico degli ultimi 7 giorni")
                        .font(.caption2).foregroundStyle(.secondary)

                    if avgLoad > 0 {
                        Divider()
                        HStack {
                            Text(LocalizedStringKey(avgLabel))
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
        pushTrainingLoad()
        guard let uuid = session.hkWorkoutUUID else { return }
        Task {
            if let v = value {
                await healthRepo.saveWorkoutEffort(rpe: v, forWorkoutUUID: uuid)
            } else {
                await healthRepo.removeWorkoutEffort(forWorkoutUUID: uuid)
            }
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

    private func remove(alsoFromHealth: Bool) {
        let uuid = session.hkWorkoutUUID
        healthRepo.deleteWorkout(session, in: modelContext)   // exclude + local delete
        GoalsSyncService.shared.sendExcludedWorkouts(Array(HealthKitRepository.excludedWorkoutUUIDs()))
        pushTrainingLoad()
        if alsoFromHealth, let uuid {
            Task { _ = await healthRepo.deleteHealthKitWorkout(uuid: uuid) }
        }
        dismiss()
    }
}
