import SwiftUI
import SwiftData
import HealthKit
import MapKit
import CoreLocation
import Charts
import FitSyncCore

// MARK: - Workout List

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyWorkoutView(onSync: { Task { await syncHealthKit() } })
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(destination: WorkoutDetailView(session: session)) {
                                if session.source == .healthKit {
                                    HealthKitWorkoutRow(session: session)
                                } else {
                                    WorkoutRow(session: session)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Allenamenti")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { Task { await syncHealthKit() } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .task { await syncHealthKit() }
            .refreshable { await syncHealthKit() }
        }
    }

    private func syncHealthKit() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await healthRepo.importHealthKitWorkouts(into: modelContext)
    }
}

// MARK: - Hevy Workout Row

struct WorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title).font(.headline)
                Spacer()
                SourceBadge(source: session.source)
            }
            Text(session.startTime, format: .dateTime.day().month().year())
                .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
            HStack(spacing: 16) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                Label("\(session.sets.count) serie", systemImage: "list.bullet")
                if session.totalVolumeKg > 0 {
                    Label("\(Int(session.totalVolumeKg / 1000))k kg", systemImage: "scalemass")
                }
            }
            .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
            if !session.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(session.muscleGroups.prefix(3), id: \.self) { group in
                        Text(group.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(FitSyncTheme.workout.opacity(0.12), in: Capsule())
                            .foregroundStyle(FitSyncTheme.workout)
                    }
                    if session.muscleGroups.count > 3 {
                        Text("+\(session.muscleGroups.count - 3)")
                            .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Apple Health Workout Row

struct HealthKitWorkoutRow: View {
    let session: WorkoutSession

    var activitySymbol: String {
        HKWorkoutActivityType(rawValue: UInt(session.hkActivityType))?.fitSyncSymbol
            ?? "figure.mixed.cardio"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(session.title, systemImage: activitySymbol).font(.headline)
                Spacer()
                SourceBadge(source: .healthKit)
            }
            Text(session.startTime, format: .dateTime.day().month().year())
                .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
            HStack(spacing: 16) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                if session.activeCalories > 0 {
                    Label("\(Int(session.activeCalories)) kcal", systemImage: "bolt.fill")
                        .foregroundStyle(.red)
                }
                if session.distanceMeters > 100 {
                    Label(formattedDistance, systemImage: "arrow.forward")
                        .foregroundStyle(.cyan)
                }
            }
            .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String {
        session.distanceMeters >= 1000
            ? String(format: "%.2f km", session.distanceMeters / 1000)
            : String(format: "%.0f m", session.distanceMeters)
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: DataSource
    var color: Color { source == .hevy ? .purple : source == .healthKit ? .red : .gray }
    var icon: String {
        switch source {
        case .hevy: return "h.circle.fill"
        case .healthKit: return "heart.fill"
        case .manual: return "pencil.circle.fill"
        }
    }
    var body: some View {
        Label(source.rawValue, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Empty State

struct EmptyWorkoutView: View {
    let onSync: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "dumbbell")
                .font(.system(size: 64))
                .foregroundStyle(FitSyncTheme.workout.opacity(0.5))
            VStack(spacing: 8) {
                Text("Nessun allenamento")
                    .font(.title3.bold())
                Text("I tuoi allenamenti Apple Fitness appaiono qui automaticamente.")
                    .font(.subheadline)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onSync) {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text("Sincronizza ora").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(FitSyncTheme.cardPadding)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
            }
        }
        .padding(FitSyncTheme.pagePadding)
    }
}

// MARK: - Route Zone Segment

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

    // Assign a zone index (1-5) to each GPS point by finding the nearest HR sample
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

    // Group consecutive same-zone points; include the transition point in both
    // adjacent segments so there are no visual gaps between polylines.
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

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    @EnvironmentObject private var healthRepo: HealthKitRepository
    let session: WorkoutSession

    @State private var hrData: WorkoutHeartRateData?
    @State private var routeLocations: [CLLocation] = []
    @State private var routeSegments: [RouteSegment] = []
    @State private var isLoadingHR = false

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
            VStack(alignment: .leading, spacing: FitSyncTheme.gap) {

                // MARK: Header stats
                FitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            let symbol = HKWorkoutActivityType(rawValue: UInt(session.hkActivityType))?.fitSyncSymbol ?? "dumbbell"
                            Image(systemName: symbol).font(.title2)
                                .foregroundStyle(session.source == .healthKit ? .red : FitSyncTheme.workout)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title).font(.headline)
                                Text(session.startTime, format: .dateTime.weekday(.wide).day().month().year())
                                    .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                            }
                            Spacer()
                            SourceBadge(source: session.source)
                        }
                        Divider()
                        HStack(spacing: 0) {
                            StatItem(value: "\(session.durationMinutes)", label: "minuti", icon: "clock")
                            if session.activeCalories > 0 {
                                Divider().frame(height: 40)
                                StatItem(value: "\(Int(session.activeCalories))", label: "kcal attive", icon: "bolt.fill")
                            }
                            if session.distanceMeters > 100 {
                                Divider().frame(height: 40)
                                let (dist, unit) = session.distanceMeters >= 1000
                                    ? (String(format: "%.2f", session.distanceMeters / 1000), "km")
                                    : (String(format: "%.0f", session.distanceMeters), "m")
                                StatItem(value: dist, label: unit, icon: "arrow.forward")
                            }
                            if session.sets.count > 0 {
                                Divider().frame(height: 40)
                                StatItem(value: "\(session.sets.count)", label: "serie", icon: "list.bullet")
                            }
                        }
                    }
                }

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

                                // HR Line Chart — downsample to ≤60 pts to avoid dense zigzag
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

                                // Zone legend (only when HR data is available)
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

                // MARK: Exercise sets (Hevy)
                ForEach(setsByExercise, id: \.0) { exerciseName, sets in
                    FitCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(sets.first?.exercise?.muscleGroup.sfSymbol ?? "dumbbell")
                                Text(exerciseName).font(.subheadline.bold())
                                Spacer()
                                if let group = sets.first?.exercise?.muscleGroup {
                                    Text(group.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(FitSyncTheme.workout.opacity(0.12), in: Capsule())
                                        .foregroundStyle(FitSyncTheme.workout)
                                }
                            }
                            HStack {
                                Text("Serie").frame(width: 40, alignment: .leading)
                                Text("Tipo").frame(width: 80, alignment: .leading)
                                Text("Peso").frame(maxWidth: .infinity, alignment: .center)
                                Text("Reps").frame(width: 50, alignment: .trailing)
                            }
                            .font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
                            Divider()
                            ForEach(sets) { set in
                                HStack {
                                    Text("#\(set.setIndex + 1)")
                                        .frame(width: 40, alignment: .leading)
                                        .font(.caption).foregroundStyle(FitSyncTheme.textSecondary)
                                    Text(set.setType.displayName)
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
            .padding(FitSyncTheme.pagePadding)
        }
        .navigationTitle(session.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        case .normal: return FitSyncTheme.textSecondary
        case .warmup: return .blue
        case .dropSet: return .orange
        case .failure: return .red
        }
    }
}

// MARK: - HR zone horizontal bars

struct HRZonesChart: View {
    let zones: HRZones

    private var zoneData: [(String, Double, Color, String)] {
        [
            ("Z1 Recovery",  zones.z1, Color.blue,   "<60%"),
            ("Z2 Brucia ♥", zones.z2, Color.green,  "60-70%"),
            ("Z3 Aerobico",  zones.z3, Color.yellow, "70-80%"),
            ("Z4 Soglia",    zones.z4, Color.orange, "80-90%"),
            ("Z5 Peak",      zones.z5, Color.red,    ">90%")
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(zoneData, id: \.0) { name, secs, color, range in
                let fraction = zones.total > 0 ? secs / zones.total : 0
                HStack(spacing: 8) {
                    Text(name).font(.caption2).frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)).frame(height: 18)
                            RoundedRectangle(cornerRadius: 4).fill(color)
                                .frame(width: geo.size.width * fraction, height: 18)
                        }
                    }
                    .frame(height: 18)
                    Text(secs > 0 ? formatTime(secs) : "—")
                        .font(.caption2.bold()).foregroundStyle(color).frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return m > 0 ? "\(m)m\(sec > 0 ? "\(sec)s" : "")" : "\(sec)s"
    }
}

struct HeartStatItem: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatItem: View {
    let value: String; let label: String; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(FitSyncTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// WorkoutViewModel removed — all data comes from HealthKit via WorkoutListView directly.
