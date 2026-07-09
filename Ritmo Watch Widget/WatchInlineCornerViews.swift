import SwiftUI
import WidgetKit

struct WatchInlineView: View {
    let entry: WatchWidgetEntry

    var body: some View {
        Label("Score \(entry.snapshot.dayScore) · \(entry.snapshot.steps / 1000)k passi",
              systemImage: "figure.run")
    }
}

struct WatchCornerView: View {
    let entry: WatchWidgetEntry

    var body: some View {
        Gauge(value: Double(entry.snapshot.dayScore), in: 0...100) {
            Text("R").font(.system(size: 8, weight: .bold))
        } currentValueLabel: {
            Text("\(entry.snapshot.dayScore)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(entry.snapshot.dayScore))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(scoreColor(entry.snapshot.dayScore))
    }
}
