import WidgetKit
import SwiftUI
import FitSyncCore

// MARK: - Shared Provider

struct FitSyncWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FitSyncEntry {
        FitSyncEntry(date: .now, snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (FitSyncEntry) -> Void) {
        completion(FitSyncEntry(date: .now, snapshot: .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FitSyncEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .placeholder
        let entry = FitSyncEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
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

struct FitSyncEntry: TimelineEntry {
    let date: Date
    let snapshot: DailySnapshot
}

// MARK: - Widget Bundle

@main
struct FitSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyScoreWidget()
        MacroGoalsWidget()
        ActivityWidget()
    }
}

// MARK: - 1. Daily Score Widget

struct DailyScoreWidget: Widget {
    let kind = "DailyScoreWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FitSyncWidgetProvider()) { entry in
            DailyScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "fitsync://dashboard")!)
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
    let entry: FitSyncEntry
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
    let icon: String; let color: Color; let label: String
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
            Image(systemName: "star.fill")
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
                Label(s.hasWorkedOutToday ? "Allenato" : "Riposo",
                      systemImage: s.hasWorkedOutToday ? "dumbbell.fill" : "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(s.hasWorkedOutToday ? .purple : .secondary)
            }
            HStack(spacing: 10) {
                Label("\(Int(s.activeCalories))kcal", systemImage: "bolt.fill").foregroundStyle(.red)
                Label(s.steps >= 1000
                      ? String(format: "%.1fk", Double(s.steps) / 1000)
                      : "\(s.steps)", systemImage: "figure.walk").foregroundStyle(.cyan)
                Label("\(Int(s.calories))kcal", systemImage: "fork.knife").foregroundStyle(.orange)
            }
            .font(.caption)
        }
    }
}

// MARK: - 2. Macro Goals Widget

struct MacroGoalsWidget: Widget {
    let kind = "MacroGoalsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FitSyncWidgetProvider()) { entry in
            MacroGoalsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "fitsync://nutrition")!)
        }
        .configurationDisplayName("Obiettivi Macro")
        .description("Calorie mangiate, proteine, carboidrati e grassi verso l'obiettivo.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MacroGoalsWidgetView: View {
    let entry: FitSyncEntry
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
                    Text("\(Int(s.calories))")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("/ \(Int(s.calorieGoal)) kcal")
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
    let icon: String; let label: String
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

// MARK: - 3. Activity Widget

struct ActivityWidget: Widget {
    let kind = "ActivityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FitSyncWidgetProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "fitsync://dashboard")!)
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
    let entry: FitSyncEntry
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
                    Text("\(Int(s.activeCalories))")
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
                    Text("\(Int(s.calories))")
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
                                  value: "\(Int(s.activeCalories))", unit: "kcal", label: "Attivi")
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
                                  value: "\(Int(s.calories))", unit: "kcal", label: "Mangiati")
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
    let value: String; let unit: String; let label: String
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
            Image(systemName: "figure.walk")
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
                Label("\(Int(s.activeCalories)) kcal", systemImage: "bolt.fill").foregroundStyle(.red)
                Label(s.steps >= 1000
                      ? String(format: "%.1fk", Double(s.steps) / 1000)
                      : "\(s.steps)", systemImage: "figure.walk").foregroundStyle(.cyan)
                Label("\(Int(s.calories)) kcal", systemImage: "fork.knife").foregroundStyle(.orange)
            }
            .font(.caption.bold())
            HStack(spacing: 10) {
                Label("\(Int(s.protein))g", systemImage: "p.circle.fill").foregroundStyle(.red)
                Label("\(Int(s.carbs))g", systemImage: "c.circle.fill").foregroundStyle(.yellow)
                Label("\(Int(s.fat))g", systemImage: "f.circle.fill").foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared helpers

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
