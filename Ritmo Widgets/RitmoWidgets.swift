import WidgetKit
import SwiftUI
import RitmoCore

// MARK: - Shared Provider

struct RitmoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RitmoEntry {
        RitmoEntry(date: .now, snapshot: .placeholder)
    }
    // Invented numbers belong in the gallery preview above and nowhere else:
    // on the home screen an un-synced widget shows zeros, not fiction.
    func getSnapshot(in context: Context, completion: @escaping (RitmoEntry) -> Void) {
        completion(RitmoEntry(date: .now, snapshot: loadSnapshot() ?? DailySnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RitmoEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? DailySnapshot()
        let entry = RitmoEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
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

struct RitmoEntry: TimelineEntry {
    let date: Date
    let snapshot: DailySnapshot
}

// MARK: - Widget Bundle

@main
struct RitmoWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyScoreWidget()
        MacroGoalsWidget()
        ActivityWidget()
        OggiWidget()
        MeetCountdownWidget()
    }
}

// MARK: - Meet countdown widget

struct MeetEntry: TimelineEntry {
    let date: Date
    let meetDate: Date?
}

struct MeetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeetEntry {
        MeetEntry(date: .now, meetDate: Calendar.current.date(byAdding: .day, value: 42, to: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (MeetEntry) -> Void) {
        completion(MeetEntry(date: .now, meetDate: HealthKitRepository.cachedMeetDate()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MeetEntry>) -> Void) {
        let entry = MeetEntry(date: .now, meetDate: HealthKitRepository.cachedMeetDate())
        // Refresh at midnight so the day count ticks without opening the app.
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct MeetCountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MeetEntry

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
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "flag.checkered").font(.system(size: 11))
                    if let days = daysToMeet {
                        Text("\(days)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("gg").font(.system(size: 8)).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 18, weight: .bold))
                    }
                }
            case .accessoryInline:
                if let days = daysToMeet {
                    Label {
                        Text(String(format: AppLocalization.string("Gara tra %@ giorni"), "\(days)"))
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                } else {
                    Label("Nessuna gara programmata", systemImage: "flag.checkered")
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .font(.headline).foregroundStyle(.orange)
                        Spacer()
                    }
                    Spacer(minLength: 0)
                    if let days = daysToMeet, let meetDate = entry.meetDate {
                        Text("\(days)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(String(format: AppLocalization.string("giorni alla gara"), "\(days)"))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(meetDate, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2.bold()).foregroundStyle(.orange)
                    } else {
                        Text("Nessuna gara programmata")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ritmo://workouts"))
    }
}

struct MeetCountdownWidget: Widget {
    let kind = "RitmoMeetCountdown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeetProvider()) { entry in
            MeetCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Conto alla rovescia gara")
        .description("Giorni alla prossima gara programmata.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Oggi widget (daily recommendation + day score)

struct OggiEntry: TimelineEntry {
    let date: Date
    let snapshot: DailySnapshot
    let recommendation: DailyRecommendation?
}

struct OggiProvider: TimelineProvider {
    func placeholder(in context: Context) -> OggiEntry {
        OggiEntry(date: .now, snapshot: .placeholder, recommendation: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (OggiEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OggiEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> OggiEntry {
        var snapshot = DailySnapshot()   // zeros until the phone has synced
        if let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.ritmo"),
           let data = defaults.data(forKey: "dailySnapshot"),
           let decoded = try? JSONDecoder().decode(DailySnapshot.self, from: data) {
            snapshot = decoded
        }
        // A recommendation is only valid for its own day.
        let recommendation = HealthKitRepository.cachedDailyRecommendation()
            .flatMap { Calendar.current.isDateInToday($0.computedOn) ? $0 : nil }
        return OggiEntry(date: .now, snapshot: snapshot, recommendation: recommendation)
    }
}

struct OggiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OggiEntry

    private func kindColor(_ kind: DailyRecommendation.Kind) -> Color {
        switch kind {
        case .push:     return .green
        case .maintain: return .cyan
        case .easy:     return .orange
        case .rest:     return .red
        case .done:     return .teal
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                if let plan = entry.recommendation {
                    HStack(spacing: 6) {
                        Image(systemName: plan.kind.icon)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(plan.kind.title))
                                .font(.system(size: 12, weight: .semibold))
                            Text(plan.reason)
                                .font(.system(size: 9))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.dashed")
                        Text("Apri Ritmo per il consiglio di oggi")
                            .font(.system(size: 10))
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let plan = entry.recommendation {
                            Image(systemName: plan.kind.icon)
                                .font(.headline)
                                .foregroundStyle(kindColor(plan.kind))
                        } else {
                            Image(systemName: "waveform.path.ecg")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.snapshot.dayScore)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    if let plan = entry.recommendation {
                        Text(LocalizedStringKey(plan.kind.title))
                            .font(.subheadline.bold())
                            .foregroundStyle(kindColor(plan.kind))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Text(plan.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Spacer(minLength: 0)
                        Text("Apri Ritmo per il consiglio di oggi")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ritmo://oggi"))
    }
}

struct OggiWidget: Widget {
    let kind = "RitmoOggi"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OggiProvider()) { entry in
            OggiWidgetView(entry: entry)
        }
        .configurationDisplayName("Oggi")
        .description("Consiglio del giorno e punteggio.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Shared helpers

func formatKilo(_ value: Double) -> String {
    value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))"
}

struct WProgressBar: View {
    let value: Double; let color: Color; let height: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2)).frame(height: height)
                RoundedRectangle(cornerRadius: 4).fill(color)
                    .frame(width: geo.size.width * min(value, 1), height: height)
            }
        }
        .frame(height: height)
    }
}
