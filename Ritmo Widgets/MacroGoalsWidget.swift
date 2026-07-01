import WidgetKit
import SwiftUI
import RitmoCore

struct MacroGoalsWidget: Widget {
    let kind = "MacroGoalsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RitmoWidgetProvider()) { entry in
            MacroGoalsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "ritmo://nutrition")!)
        }
        .configurationDisplayName("Obiettivi Macro")
        .description("Calorie mangiate, proteine, carboidrati e grassi verso l'obiettivo.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MacroGoalsWidgetView: View {
    let entry: RitmoEntry
    @Environment(\.widgetFamily) var family
    var s: DailySnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nutrizione").font(.headline.bold())
                    Text(entry.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatKilo(s.calories))
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("/ \(formatKilo(s.calorieGoal)) kcal")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if family == .systemLarge {
                WProgressBar(value: s.calories / max(s.calorieGoal, 1), color: .orange, height: 6)
                    .padding(.bottom, 2)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MacroCell(icon: "🥩", label: "Proteine",
                          current: s.protein, goal: s.proteinGoal, unit: "g", color: .red)
                MacroCell(icon: "🍞", label: "Carbs",
                          current: s.carbs, goal: s.carbsGoal, unit: "g", color: .yellow)
                MacroCell(icon: "🥑", label: "Grassi",
                          current: s.fat, goal: s.fatGoal, unit: "g", color: .green)
                if family == .systemLarge {
                    MacroCell(icon: "🌾", label: "Fibre",
                              current: s.fiber, goal: s.fiberGoal, unit: "g", color: .mint)
                } else {
                    MacroCell(icon: "💧", label: "Acqua",
                              current: s.waterMl / 1000, goal: s.waterGoal / 1000, unit: "L", color: .blue)
                }
            }

            if family == .systemLarge {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue).font(.caption)
                    Text("Acqua").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f / %.1fL", s.waterMl / 1000, s.waterGoal / 1000))
                        .font(.caption.bold())
                }
                WProgressBar(value: s.waterMl / max(s.waterGoal, 1), color: .blue, height: 5)
            }
        }
        .padding(12)
    }
}

struct MacroCell: View {
    let icon: String; let label: LocalizedStringKey
    let current: Double; let goal: Double; let unit: String; let color: Color
    var progress: Double { min(current / max(goal, 1), 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(icon).font(.caption)
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if progress >= 1 {
                    Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                }
            }
            Text("\(Int(current))\(unit)")
                .font(.system(.callout, design: .rounded, weight: .bold))
            WProgressBar(value: progress, color: progress >= 1 ? .green : color, height: 5)
            Text("su \(Int(goal))\(unit)")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
