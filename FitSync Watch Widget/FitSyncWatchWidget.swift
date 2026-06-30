import WidgetKit
import SwiftUI
import FitSyncCore

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
        guard let defaults = UserDefaults(suiteName: "group.alessandrodiscalzi.com.fitsync"),
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

struct FitSyncWatchWidget: Widget {
    let kind = "FitSyncWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("FitSync")
        .description("Score giornaliero, passi, calorie e sonno.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

@main
struct FitSyncWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        FitSyncWatchWidget()
    }
}
