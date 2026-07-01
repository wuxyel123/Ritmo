import WidgetKit
import SwiftUI
import RitmoCore

// MARK: - Shared Provider

struct RitmoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RitmoEntry {
        RitmoEntry(date: .now, snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (RitmoEntry) -> Void) {
        completion(RitmoEntry(date: .now, snapshot: .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RitmoEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .placeholder
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
