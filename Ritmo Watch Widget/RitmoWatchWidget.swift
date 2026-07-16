import WidgetKit
import SwiftUI
import RitmoCore

// MARK: - Provider

struct WatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWidgetEntry {
        WatchWidgetEntry(date: .now, snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchWidgetEntry) -> Void) {
        completion(WatchWidgetEntry(date: .now, snapshot: loadSnapshot() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWidgetEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .placeholder
        let entry = WatchWidgetEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func loadSnapshot() -> DailySnapshot? {
        guard let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo"),
              let data = defaults.data(forKey: "dailySnapshot"),
              let snap = try? JSONDecoder().decode(DailySnapshot.self, from: data)
        else { return nil }
        return snap
    }
}

struct WatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DailySnapshot
}

// MARK: - Complication Router

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:    WatchCircularView(entry: entry)
        case .accessoryRectangular: WatchRectangularView(entry: entry)
        case .accessoryInline:      WatchInlineView(entry: entry)
        case .accessoryCorner:      WatchCornerView(entry: entry)
        default:                    WatchCircularView(entry: entry)
        }
    }
}

// MARK: - Widget

struct RitmoWatchWidget: Widget {
    let kind = "RitmoWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Ritmo")
        .description("Score giornaliero, passi, calorie e sonno.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Rings complication (single circular tile)

struct WatchRingsView: View {
    let entry: WatchWidgetEntry

    private var calPct: Double {
        entry.snapshot.activeCalories / max(entry.snapshot.activeCalorieGoal, 1)
    }
    private var stepPct: Double {
        Double(entry.snapshot.steps) / Double(max(entry.snapshot.stepGoal, 1))
    }
    private var sleepPct: Double { entry.snapshot.sleepHours / 8.0 }

    var body: some View {
        GeometryReader { geo in
            let lineW = min(geo.size.width, geo.size.height) * 0.13
            ZStack {
                ring(calPct,   .red,  lineW)
                ring(stepPct,  .green, lineW).padding(lineW * 1.7)
                ring(sleepPct, .cyan, lineW).padding(lineW * 3.4)
            }
        }
    }

    private func ring(_ pct: Double, _ color: Color, _ lineW: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: lineW)
            Circle()
                .trim(from: 0, to: min(max(pct, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineW, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// Labeled rectangular version of the same three ring metrics.
struct WatchRingsRectangularView: View {
    let entry: WatchWidgetEntry

    private var calPct: Double {
        entry.snapshot.activeCalories / max(entry.snapshot.activeCalorieGoal, 1)
    }
    private var stepPct: Double {
        Double(entry.snapshot.steps) / Double(max(entry.snapshot.stepGoal, 1))
    }
    private var sleepPct: Double { entry.snapshot.sleepHours / 8.0 }

    var body: some View {
        HStack(spacing: 4) {
            WatchMetricCell(icon: "🔥",
                            value: "\(Int(entry.snapshot.activeCalories))",
                            pct: calPct, color: .red)
            WatchMetricCell(icon: "🚶",
                            value: "\(entry.snapshot.steps / 1000)k",
                            pct: stepPct, color: .green)
            WatchMetricCell(icon: "😴",
                            value: String(format: "%.1fh", entry.snapshot.sleepHours),
                            pct: sleepPct, color: .cyan)
        }
    }
}

struct RingsComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: WatchRingsRectangularView(entry: entry)
        default:                    WatchRingsView(entry: entry)
        }
    }
}

struct RitmoRingsWidget: Widget {
    let kind = "RitmoRingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            RingsComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Ritmo Anelli")
        .description("Calorie attive, passi e sonno — anelli o valori.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Days since last workout

struct DaysSinceWorkoutEntry: TimelineEntry {
    let date: Date
    let daysSince: Int?          // nil = no workout on record
    let workedOutToday: Bool
}

struct DaysSinceWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysSinceWorkoutEntry {
        DaysSinceWorkoutEntry(date: .now, daysSince: 2, workedOutToday: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (DaysSinceWorkoutEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysSinceWorkoutEntry>) -> Void) {
        // Refresh at the next midnight so the day count ticks over on its own.
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 3600)
        completion(Timeline(entries: [load()], policy: .after(midnight)))
    }

    private func load() -> DaysSinceWorkoutEntry {
        let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo")
        let epoch = defaults?.double(forKey: "lastWorkoutDate") ?? 0
        var days: Int? = nil
        var today = false
        if epoch > 0 {
            let last = Date(timeIntervalSince1970: epoch)
            let calendar = Calendar.current
            days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
            today = calendar.isDateInToday(last)
        }
        // The snapshot flag also covers workouts imported on the phone side.
        if let data = defaults?.data(forKey: "dailySnapshot"),
           let snap = try? JSONDecoder().decode(DailySnapshot.self, from: data),
           snap.hasWorkedOutToday, Calendar.current.isDateInToday(snap.date) {
            today = true
            days = 0
        }
        return DaysSinceWorkoutEntry(date: .now, daysSince: days, workedOutToday: today)
    }
}

struct DaysSinceWorkoutView: View {
    @Environment(\.widgetFamily) var family
    let entry: DaysSinceWorkoutEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if entry.workedOutToday {
                Label("Allenato oggi ✓", systemImage: "checkmark.seal.fill")
            } else if let days = entry.daysSince {
                Label("\(days)g dall'allenamento", systemImage: "dumbbell.fill")
            } else {
                Label("Nessun allenamento", systemImage: "dumbbell")
            }
        default:
            ZStack {
                if entry.workedOutToday {
                    // Trained today → the "done" face.
                    VStack(spacing: 1) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.green)
                        Text("oggi")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else if let days = entry.daysSince {
                    // Days since the last workout.
                    VStack(spacing: 0) {
                        Text("\(days)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(days >= 3 ? .orange : .primary)
                        HStack(spacing: 2) {
                            Image(systemName: "dumbbell.fill").font(.system(size: 8))
                            Text(days == 1 ? "giorno" : "giorni")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RitmoDaysSinceWorkoutWidget: Widget {
    let kind = "RitmoDaysSinceWorkout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DaysSinceWorkoutProvider()) { entry in
            DaysSinceWorkoutView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Giorni dall'allenamento")
        .description("Giorni dall'ultimo allenamento — spunta verde se ti sei già allenato oggi.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

// MARK: - Meet countdown complication

struct MeetCountdownEntry: TimelineEntry {
    let date: Date
    let meetDate: Date?
}

struct MeetCountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeetCountdownEntry {
        MeetCountdownEntry(date: .now,
                           meetDate: Calendar.current.date(byAdding: .day, value: 42, to: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (MeetCountdownEntry) -> Void) {
        completion(MeetCountdownEntry(date: .now, meetDate: HealthKitRepository.cachedMeetDate()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MeetCountdownEntry>) -> Void) {
        let entry = MeetCountdownEntry(date: .now, meetDate: HealthKitRepository.cachedMeetDate())
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct MeetCountdownComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MeetCountdownEntry

    private var daysToMeet: Int? {
        guard let meetDate = entry.meetDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: meetDate)).day ?? -1
        return days >= 0 ? days : nil
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let days = daysToMeet {
                    Label {
                        Text(String(format: NSLocalizedString("Gara tra %@ giorni", comment: ""), "\(days)"))
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                } else {
                    Label("Nessuna gara programmata", systemImage: "flag.checkered")
                }
            default:
                VStack(spacing: 0) {
                    Image(systemName: "flag.checkered").font(.system(size: 10))
                    if let days = daysToMeet {
                        Text("\(days)")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("gg").font(.system(size: 8)).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 17, weight: .bold))
                    }
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct RitmoMeetCountdownWidget: Widget {
    let kind = "RitmoMeetCountdown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeetCountdownProvider()) { entry in
            MeetCountdownComplicationView(entry: entry)
        }
        .configurationDisplayName("Conto alla rovescia gara")
        .description("Giorni alla prossima gara programmata.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

@main
struct RitmoWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RitmoWatchWidget()
        RitmoRingsWidget()
        RitmoDaysSinceWorkoutWidget()
        RitmoMeetCountdownWidget()
    }
}
