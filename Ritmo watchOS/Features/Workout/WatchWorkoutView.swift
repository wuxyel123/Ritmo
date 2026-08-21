import SwiftUI
import RitmoCore

struct WatchWorkoutView: View {
    let goals: UserGoals
    let sessions: [WorkoutSession]
    @EnvironmentObject private var vm: WatchViewModel
    @State private var isRefreshing = false

    private var todaySessions: [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: .now)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return sessions.filter { $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime > $1.startTime }
    }

    @ViewBuilder
    private var trainingLoadCard: some View {
        // Prefer the iPhone's ground-truth value; fall back to a local compute
        // only if the phone hasn't synced one yet (standalone watch use).
        let load = vm.trainingLoad ?? TrainingLoad.compute(from: sessions)
        if load.acute > 0 || load.chronic > 0 {
            let color: Color = switch load.status {
                case .low:      .blue
                case .optimal:  .green
                case .high:     .orange
                case .veryHigh: .red
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Carico").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text(LocalizedStringKey(load.status.label))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    Text("\(load.acute)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("7gg").font(.system(size: 8)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 2) {
                        let maxV = max(load.weeklyEfforts.max() ?? 1, 1)
                        ForEach(Array(load.weeklyEfforts.enumerated()), id: \.offset) { _, v in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(v > 0 ? color : Color.gray.opacity(0.25))
                                .frame(width: 4, height: max(3, CGFloat(v) / CGFloat(maxV) * 18))
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {

                    // MARK: Header
                    Text("Allenamento")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // MARK: Training load
                    trainingLoadCard

                    // MARK: Today's sessions
                    if todaySessions.isEmpty && !vm.snapshot.hasWorkedOutToday {
                        VStack(spacing: 6) {
                            Text("💤").font(.system(size: 28))
                            Text("Nessun allenamento oggi")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    } else {
                        if vm.snapshot.hasWorkedOutToday && todaySessions.isEmpty {
                            HStack(spacing: 6) {
                                Text("✅").font(.caption)
                                Text("Allenamento completato")
                                    .font(.caption.bold()).foregroundStyle(.green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(todaySessions) { session in
                            NavigationLink {
                                WatchWorkoutDetailView(session: session)
                            } label: {
                                WatchWorkoutRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // MARK: Last session (if nothing today)
                    if todaySessions.isEmpty, let last = sessions.first(where: {
                        !Calendar.current.isDateInToday($0.startTime)
                    }) {
                        Divider()
                        Text("Ultimo allenamento")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NavigationLink {
                            WatchWorkoutDetailView(session: last)
                        } label: {
                            WatchWorkoutRow(session: last)
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: Refresh
                    Button {
                        isRefreshing = true
                        Task {
                            await vm.load(goals: goals)
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                        } else {
                            Label("Aggiorna", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Workout Row (compact summary — tap for detail)

struct WatchWorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            // Title + chevron
            HStack {
                Text(LocalizedStringKey(session.title))
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            // Duration + relative time
            HStack(spacing: 6) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Text("· \(session.startTime, style: .relative)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }

            // Muscle groups
            if !session.muscleGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(session.muscleGroups, id: \.self) { group in
                            Text(LocalizedStringKey(group.rawValue))
                                .font(.system(size: 8, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            // Summary stats
            HStack(spacing: 8) {
                if session.totalVolumeKg > 0 {
                    statChip("scalemass.fill", "\(Int(session.totalVolumeKg.rounded())) kg", .orange)
                }
                if session.sets.count > 0 {
                    statChip("list.bullet", "\(session.sets.count) serie", .blue)
                }
                if session.activeCalories > 0 {
                    statChip("flame.fill", "\(Int(session.activeCalories)) kcal", .red)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statChip(_ icon: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 7)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout Detail (mirrors the iOS WorkoutDetailView)

struct WatchWorkoutDetailView: View {
    let session: WorkoutSession

    @EnvironmentObject private var vm: WatchViewModel
    @StateObject private var healthRepo = HealthKitRepository()
    @State private var hr: WorkoutHeartRateData?
    @State private var isLoadingHR = false

    private var setsByExercise: [(String, [WorkoutSet])] {
        var groups: [(String, [WorkoutSet])] = []
        var seen: [String] = []
        for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            let name = set.exercise?.name ?? "Esercizio"
            if !seen.contains(name) {
                seen.append(name)
                groups.append((name, session.sets
                    .filter { $0.exercise?.name == name }
                    .sorted { $0.setIndex < $1.setIndex }))
            }
        }
        return groups
    }

    private var distanceText: String? {
        guard session.distanceMeters > 100 else { return nil }
        return session.distanceMeters >= 1000
            ? String(format: "%.2f km", session.distanceMeters / 1000)
            : String(format: "%.0f m", session.distanceMeters)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: Title + date
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(session.title))
                        .font(.headline).lineLimit(2)
                    Text(session.startTime, format: .dateTime.weekday().day().month())
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // MARK: Stat grid
                statGrid

                // MARK: Heart rate (Apple Health workouts)
                if session.source == .healthKit {
                    if isLoadingHR {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 6)
                    } else if let hr, !hr.samples.isEmpty {
                        heartRateSection(hr)
                        if hr.zones.total > 0 {
                            zonesSection(hr.zones)
                        }
                    }
                }

                // MARK: Exercises
                if !setsByExercise.isEmpty {
                    exercisesSection
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .navigationTitle("Dettaglio")
        .task {
            guard session.source == .healthKit else { return }
            isLoadingHR = true
            hr = await healthRepo.fetchWorkoutHeartRate(start: session.startTime, end: session.endTime)
            isLoadingHR = false
        }
    }

    // MARK: Stat grid

    private var statGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 6) {
            statTile("clock", "\(session.durationMinutes)", "min", .teal)
            statTile("gauge.with.dots.needle.50percent", "\(session.effortScore)",
                    session.hasUserRPE ? "RPE" : "RPE stima", .pink)
            if session.activeCalories > 0 {
                statTile("flame.fill", "\(Int(session.activeCalories))", "kcal", .red)
            }
            if let load = vm.trainingLoad, load.acute > 0 {
                let share = min(session.loadValue / Double(load.acute), 1.0)
                let color: Color = switch load.status {
                    case .low:      .blue
                    case .optimal:  .green
                    case .high:     .orange
                    case .veryHigh: .red
                }
                statTile("chart.bar.fill", "\(Int((share * 100).rounded()))%", "carico 7gg", color)

                // Same matched average the iPhone computed (synced inside `load`,
                // category-matched to this workout when possible) — not a local
                // recompute from the watch's own session list, which could have a
                // slightly different history and disagree with the iPhone.
                let matched = load.matchedAverageLoad(for: session)
                if matched.value > 0 {
                    let vsAveragePct = ((session.loadValue - matched.value) / matched.value) * 100
                    let vsAvgColor: Color = vsAveragePct > 10 ? .orange : (vsAveragePct < -10 ? .blue : .secondary)
                    let text = vsAveragePct >= 0 ? "+\(Int(vsAveragePct.rounded()))%" : "\(Int(vsAveragePct.rounded()))%"
                    statTile("arrow.left.arrow.right", text, "vs media", vsAvgColor)
                }
            }
            if let dist = distanceText {
                statTile("arrow.forward", dist, "distanza", .cyan)
            }
            if session.totalVolumeKg > 0 {
                statTile("scalemass.fill", String(format: "%.0f", session.totalVolumeKg), "kg vol.", .orange)
            }
            if session.sets.count > 0 {
                statTile("list.bullet", "\(session.sets.count)", "serie", .blue)
            }
        }
    }

    private func statTile(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
            Text(LocalizedStringKey(label)).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Heart rate

    private func heartRateSection(_ hr: WorkoutHeartRateData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Frequenza cardiaca", systemImage: "heart.fill")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
            HStack(spacing: 0) {
                hrStat("\(Int(hr.avgBPM))", "media", .red)
                Divider().frame(height: 26)
                hrStat("\(Int(hr.maxBPM))", "max", .orange)
                Divider().frame(height: 26)
                hrStat("\(Int(hr.minBPM))", "min", .blue)
            }
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func hrStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(LocalizedStringKey(label)).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: HR zones

    private func zonesSection(_ zones: HRZones) -> some View {
        let rows: [(Int, Double, Color)] = [
            (1, zones.z1, .blue), (2, zones.z2, .green), (3, zones.z3, .yellow),
            (4, zones.z4, .orange), (5, zones.z5, .red)
        ]
        let total = max(zones.total, 1)
        return VStack(alignment: .leading, spacing: 5) {
            Label("Zone FC", systemImage: "chart.bar.fill")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { zone, seconds, color in
                if seconds > 0 {
                    HStack(spacing: 6) {
                        Text("Z\(zone)")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                            .frame(width: 18, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2)).frame(height: 6)
                                RoundedRectangle(cornerRadius: 2).fill(color)
                                    .frame(width: geo.size.width * CGFloat(seconds / total), height: 6)
                            }
                        }
                        .frame(height: 6)
                        Text(zoneTime(seconds))
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func zoneTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    // MARK: Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Esercizi", systemImage: "dumbbell.fill")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)

            ForEach(Array(setsByExercise.enumerated()), id: \.offset) { _, pair in
                let (name, sets) = pair
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(sets.first?.exercise?.muscleGroup.sfSymbol ?? "dumbbell")
                            .font(.system(size: 11))
                        Text(name)
                            .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer()
                        if let group = sets.first?.exercise?.muscleGroup {
                            Text(LocalizedStringKey(group.rawValue))
                                .font(.system(size: 7))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    ForEach(sets) { set in
                        HStack(spacing: 0) {
                            Text("#\(set.setIndex + 1)")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text(LocalizedStringKey(set.setType.displayName))
                                .font(.system(size: 9)).foregroundStyle(setTypeColor(set.setType))
                                .frame(width: 60, alignment: .leading)
                            Spacer()
                            if set.weightKg > 0 {
                                Text(String(format: "%.1f kg", set.weightKg))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            if let reps = set.reps {
                                Text(" × \(reps)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func setTypeColor(_ type: SetType) -> Color {
        switch type {
        case .normal:  return .secondary
        case .warmup:  return .blue
        case .dropSet: return .orange
        case .failure: return .red
        }
    }
}
