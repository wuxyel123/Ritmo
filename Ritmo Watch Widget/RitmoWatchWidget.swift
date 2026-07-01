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

@main
struct RitmoWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RitmoWatchWidget()
        RitmoRingsWidget()
    }
}
