import WidgetKit
import SwiftUI
import RitmoCore

struct ActivityWidget: Widget {
    let kind = "ActivityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RitmoWidgetProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "ritmo://dashboard")!)
        }
        .configurationDisplayName("Attività")
        .description("Calorie attive, passi, calorie mangiate e macro.")
        .supportedFamilies(activityWidgetFamilies())
    }
}

private func activityWidgetFamilies() -> [WidgetFamily] {
    #if os(macOS)
    return [.systemSmall, .systemMedium]
    #else
    return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    #endif
}

struct ActivityWidgetView: View {
    let entry: RitmoEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .systemMedium:          ActivityMediumView(s: entry.snapshot)
        case .accessoryCircular:     ActivityCircularView(s: entry.snapshot)
        case .accessoryRectangular:  ActivityRectangularView(s: entry.snapshot)
        default:                     ActivitySmallView(s: entry.snapshot)
        }
    }
}

// Small — text only: active cal (big), steps + eaten below, protein/carbs/fat row
struct ActivitySmallView: View {
    let s: DailySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active calories — hero number
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(formatKilo(s.activeCalories))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.red)
                    Text("kcal").font(.caption2).foregroundStyle(.secondary)
                }
                Text("attivi").font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            // Steps + eaten
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk").font(.caption2).foregroundStyle(.cyan)
                    Text(s.steps >= 1000
                         ? String(format: "%.1fk", Double(s.steps) / 1000)
                         : "\(s.steps)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("passi").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife").font(.caption2).foregroundStyle(.orange)
                    Text(formatKilo(s.calories))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("kcal man.").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            // Macros row
            HStack(spacing: 0) {
                MiniMacroLabel(emoji: "🥩", value: Int(s.protein), unit: "g")
                Spacer()
                MiniMacroLabel(emoji: "🍞", value: Int(s.carbs), unit: "g")
                Spacer()
                MiniMacroLabel(emoji: "🥑", value: Int(s.fat), unit: "g")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MiniMacroLabel: View {
    let emoji: String; let value: Int; let unit: String
    var body: some View {
        VStack(spacing: 1) {
            Text(emoji).font(.system(size: 11))
            Text("\(value)\(unit)").font(.system(size: 9, weight: .semibold, design: .rounded))
        }
    }
}

// Medium — full text layout: 3 main stats + macro bar
struct ActivityMediumView: View {
    let s: DailySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top: 3 key stats
            HStack(spacing: 0) {
                ActivityStatBlock(icon: "bolt.fill", color: .red,
                                  value: formatKilo(s.activeCalories), unit: "kcal", label: "Attivi")
                Spacer()
                Rectangle().fill(.quaternary).frame(width: 1, height: 36)
                Spacer()
                ActivityStatBlock(icon: "figure.walk", color: .cyan,
                                  value: s.steps >= 1000
                                      ? String(format: "%.1fk", Double(s.steps) / 1000)
                                      : "\(s.steps)",
                                  unit: "", label: "Passi")
                Spacer()
                Rectangle().fill(.quaternary).frame(width: 1, height: 36)
                Spacer()
                ActivityStatBlock(icon: "fork.knife", color: .orange,
                                  value: formatKilo(s.calories), unit: "kcal", label: "Mangiati")
            }

            Divider()

            // Bottom: macros
            HStack(spacing: 0) {
                MacroStatBlock(emoji: "🥩", value: s.protein, goal: s.proteinGoal,
                               label: "Proteine", color: .red)
                Spacer()
                MacroStatBlock(emoji: "🍞", value: s.carbs, goal: s.carbsGoal,
                               label: "Carbs", color: .yellow)
                Spacer()
                MacroStatBlock(emoji: "🥑", value: s.fat, goal: s.fatGoal,
                               label: "Grassi", color: .green)
            }
        }
        .padding(14)
    }
}

private struct ActivityStatBlock: View {
    let icon: String; let color: Color
    let value: String; let unit: String; let label: LocalizedStringKey
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct MacroStatBlock: View {
    let emoji: String; let value: Double; let goal: Double; let label: String; let color: Color
    var progress: Double { min(value / max(goal, 1), 1) }
    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(emoji).font(.caption)
            Text("\(Int(value))g")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            WProgressBar(value: progress, color: progress >= 1 ? .green : color, height: 3)
                .frame(width: 44)
            Text("/ \(Int(goal))g").font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
}

// Lock screen circular — steps gauge
struct ActivityCircularView: View {
    let s: DailySnapshot
    var body: some View {
        Gauge(value: Double(s.steps), in: 0...Double(max(s.stepGoal, 1))) {
            Text("🚶")
        } currentValueLabel: {
            Text(s.steps >= 1000 ? "\(s.steps / 1000)k" : "\(s.steps)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// Lock screen rectangular — no app name, two info rows
struct ActivityRectangularView: View {
    let s: DailySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Label { Text("\(formatKilo(s.activeCalories))kcal") } icon: { Text("⚡") }.foregroundStyle(.red)
                Label { Text(s.steps >= 1000 ? String(format: "%.1fk", Double(s.steps) / 1000) : "\(s.steps)") } icon: { Text("🚶") }.foregroundStyle(.cyan)
                Label { Text("\(formatKilo(s.calories))kcal") } icon: { Text("🍽️") }.foregroundStyle(.orange)
            }
            .font(.caption.bold())
            HStack(spacing: 10) {
                Label { Text("\(Int(s.protein))g") } icon: { Text("🥩") }.foregroundStyle(.red)
                Label { Text("\(Int(s.carbs))g") } icon: { Text("🍞") }.foregroundStyle(.yellow)
                Label { Text("\(Int(s.fat))g") } icon: { Text("🥑") }.foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
