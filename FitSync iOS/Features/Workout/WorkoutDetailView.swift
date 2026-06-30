import SwiftUI
import HealthKit
import MapKit
import CoreLocation
import Charts
import FitSyncCore

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
                                Text(LocalizedStringKey(session.title)).font(.headline)
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
                                StatItem(value: dist, label: LocalizedStringKey(unit), icon: "arrow.forward")
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
            .padding(FitSyncTheme.pagePadding)
        }
        .navigationTitle(LocalizedStringKey(session.title))
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
