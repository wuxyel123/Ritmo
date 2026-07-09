import SwiftUI
import WidgetKit

struct WatchCircularView: View {
    let entry: WatchWidgetEntry

    var body: some View {
        Gauge(value: Double(entry.snapshot.dayScore), in: 0...100) {
            Text("R").font(.system(size: 8, weight: .bold))
        } currentValueLabel: {
            Text("\(entry.snapshot.dayScore)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(entry.snapshot.dayScore))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(scoreColor(entry.snapshot.dayScore))
    }
}

func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return .green
    case 60..<80: return .yellow
    default: return .orange
    }
}
