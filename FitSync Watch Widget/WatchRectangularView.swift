import SwiftUI
import WidgetKit

struct WatchRectangularView: View {
    let entry: WatchWidgetEntry

    private var stepPct: Double { Double(entry.snapshot.steps) / Double(max(entry.snapshot.stepGoal, 1)) }
    private var calPct: Double { entry.snapshot.activeCalories / max(entry.snapshot.activeCalorieGoal, 1) }
    private var sleepPct: Double { entry.snapshot.sleepHours / 8.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("FitSync")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Score")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(entry.snapshot.dayScore)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(entry.snapshot.dayScore))
            }
            ProgressView(value: Double(entry.snapshot.dayScore), total: 100)
                .tint(scoreColor(entry.snapshot.dayScore))
                .scaleEffect(x: 1, y: 1.3, anchor: .center)
            HStack(spacing: 0) {
                WatchMetricCell(icon: "🚶",
                                value: "\(entry.snapshot.steps / 1000)k",
                                pct: stepPct, color: .green)
                WatchMetricCell(icon: "🔥",
                                value: "\(Int(entry.snapshot.activeCalories))",
                                pct: calPct, color: .orange)
                WatchMetricCell(icon: "😴",
                                value: String(format: "%.1fh", entry.snapshot.sleepHours),
                                pct: sleepPct, color: .indigo)
                WatchMetricCell(icon: "🥩",
                                value: "\(Int(entry.snapshot.protein))g",
                                pct: entry.snapshot.protein / max(entry.snapshot.proteinGoal, 1),
                                color: .red)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct WatchMetricCell: View {
    let icon: String
    let value: String
    let pct: Double
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(icon).font(.system(size: 9))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ProgressView(value: min(pct, 1))
                .tint(pct >= 1 ? .green : color)
                .scaleEffect(x: 1, y: 1.2)
        }
        .frame(maxWidth: .infinity)
    }
}
