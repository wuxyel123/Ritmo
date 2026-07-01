import WidgetKit
import SwiftUI
import RitmoCore

struct DailyScoreWidget: Widget {
    let kind = "DailyScoreWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RitmoWidgetProvider()) { entry in
            DailyScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "ritmo://dashboard")!)
        }
        .configurationDisplayName("Score Giornaliero")
        .description("Il tuo punteggio composito: nutrizione, movimento e recupero.")
        .supportedFamilies(scoreWidgetFamilies())
    }
}

private func scoreWidgetFamilies() -> [WidgetFamily] {
    #if os(macOS)
    return [.systemSmall]
    #else
    return [.systemSmall, .accessoryCircular, .accessoryRectangular]
    #endif
}

struct DailyScoreWidgetView: View {
    let entry: RitmoEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .accessoryCircular:  ScoreGaugeView(s: entry.snapshot)
        case .accessoryRectangular: ScoreRectangularView(s: entry.snapshot)
        default: ScoreSmallView(s: entry.snapshot)
        }
    }
}

// Small home screen — text only, no ring
struct ScoreSmallView: View {
    let s: DailySnapshot
    var scoreColor: Color { s.dayScore >= 80 ? .green : s.dayScore >= 60 ? .yellow : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(s.dayScore)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(scoreColor)
                Text("/ 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 5) {
                ScorePillarRow(icon: "figure.walk", color: .cyan,
                               label: "Mov.", value: s.movementScore, maxScore: 40)
                ScorePillarRow(icon: "moon.fill", color: .indigo,
                               label: "Rec.", value: s.recoveryScore, maxScore: 30)
                ScorePillarRow(icon: "fork.knife", color: .orange,
                               label: "Nut.", value: s.nutritionScore, maxScore: 20)
                ScorePillarRow(icon: "dumbbell.fill", color: .purple,
                               label: "All.", value: s.workoutBonus, maxScore: 10)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct ScorePillarRow: View {
    let icon: String; let color: Color; let label: LocalizedStringKey
    let value: Double; let maxScore: Double
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color).frame(width: 12)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
            WProgressBar(value: value / Swift.max(maxScore, 1), color: color, height: 4)
            Text("\(Int(value))").font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(color).frame(width: 18, alignment: .trailing)
        }
    }
}

// Lock screen circular — gauge
struct ScoreGaugeView: View {
    let s: DailySnapshot
    var body: some View {
        Gauge(value: Double(s.dayScore), in: 0...100) {
            Text("⭐")
        } currentValueLabel: {
            Text("\(s.dayScore)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// Lock screen rectangular — no app name
struct ScoreRectangularView: View {
    let s: DailySnapshot
    var scoreColor: Color { s.dayScore >= 80 ? .green : s.dayScore >= 60 ? .yellow : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(s.dayScore)").font(.headline.bold()).foregroundStyle(scoreColor)
                Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Label {
                    if s.hasWorkedOutToday { Text("Allenato") } else { Text("Riposo") }
                } icon: {
                    Text(s.hasWorkedOutToday ? "💪" : "🌙")
                }
                .font(.caption2)
                .foregroundStyle(s.hasWorkedOutToday ? .purple : .secondary)
            }
            HStack(spacing: 10) {
                Label { Text("\(formatKilo(s.activeCalories))kcal") } icon: { Text("⚡") }.foregroundStyle(.red)
                Label { Text(s.steps >= 1000 ? String(format: "%.1fk", Double(s.steps) / 1000) : "\(s.steps)") } icon: { Text("🚶") }.foregroundStyle(.cyan)
                Label { Text("\(formatKilo(s.calories))kcal") } icon: { Text("🍽️") }.foregroundStyle(.orange)
            }
            .font(.caption)
        }
    }
}
