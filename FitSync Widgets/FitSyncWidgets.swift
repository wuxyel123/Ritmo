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
        case .accessoryCircular: ScoreGaugeView(s: entry.snapshot)
        case .accessoryRectangular: ScoreRectangularView(s: entry.snapshot)
        default: ScoreSmallView(s: entry.snapshot)
        }
    }
}
// widgetURL is set per-family via Link or at view level; for simplicity set on the containing view in the Widget config


struct ScoreSmallView: View {
    let s: DailySnapshot
    var color: Color { s.dayScore >= 80 ? .green : s.dayScore >= 60 ? .yellow : .orange }
    var body: some View {
        VStack(spacing: 6) {
            Text("FitSync")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(s.dayScore) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(s.dayScore)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("/ 100")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            Label(s.hasWorkedOutToday ? "Allenato" : "Riposo",
                  systemImage: s.hasWorkedOutToday ? "dumbbell.fill" : "moon.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

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

struct ScoreRectangularView: View {
    let s: DailySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("FitSync  Score \(s.dayScore)/100").font(.headline)
            }
            HStack(spacing: 10) {
                Label("\(Int(s.calories))kcal", systemImage: "fork.knife")
                Label("\(Int(s.activeCalories))kcal", systemImage: "bolt.fill").foregroundStyle(.red)
                Label(s.steps.formatted(), systemImage: "figure.walk").foregroundStyle(.cyan)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
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

// MARK: - 3. Activity Widget (rimpiazza NutritionRingWidget)

struct ActivityWidget: Widget {
    let kind = "ActivityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FitSyncWidgetProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "fitsync://dashboard")!)
        }
        .configurationDisplayName("Attività")
        .description("Calorie attive, passi e calorie mangiate — i 3 anelli del tuo stile di vita.")
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
        case .systemMedium: ActivityMediumView(s: entry.snapshot)
        case .accessoryCircular: ActivityCircularView(s: entry.snapshot)
        case .accessoryRectangular: ActivityRectangularView(s: entry.snapshot)
        default: ActivitySmallView(s: entry.snapshot)
        }
    }
}

// Small: 3 rings + bottom stats
struct ActivitySmallView: View {
    let s: DailySnapshot
    var stepsP: Double { min(Double(s.steps) / Double(max(s.stepGoal, 1)), 1) }
    var calP: Double { min(s.calories / max(s.calorieGoal, 1), 1) }
    var activeP: Double { min(s.activeCalories / max(s.activeCalorieGoal, 1), 1) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer ring — passi (cyan)
                ActivityRing(progress: stepsP, color: .cyan, lineWidth: 9, padding: 0)
                // Middle ring — calorie mangiate (orange)
                ActivityRing(progress: calP, color: .orange, lineWidth: 7, padding: 11)
                // Inner ring — calorie attive (red, come Move ring)
                ActivityRing(progress: activeP, color: .red, lineWidth: 5, padding: 21)
                // Centre shows active cal burned
                VStack(spacing: 0) {
                    Text("\(Int(s.activeCalories))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("attivi")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)

            HStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text(s.steps >= 1000
                         ? String(format: "%.1fk", Double(s.steps) / 1000)
                         : "\(s.steps)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("passi").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Divider().frame(height: 18)
                VStack(spacing: 1) {
                    Text("\(Int(s.calories))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("kcal man.").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
    }
}

// Medium: rings on left, metrics on right
struct ActivityMediumView: View {
    let s: DailySnapshot
    var stepsP: Double { min(Double(s.steps) / Double(max(s.stepGoal, 1)), 1) }
    var calP: Double { min(s.calories / max(s.calorieGoal, 1), 1) }
    var activeP: Double { min(s.activeCalories / max(s.activeCalorieGoal, 1), 1) }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ActivityRing(progress: stepsP, color: .cyan, lineWidth: 10, padding: 0)
                ActivityRing(progress: calP, color: .orange, lineWidth: 8, padding: 13)
                ActivityRing(progress: activeP, color: .red, lineWidth: 6, padding: 24)
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10)).foregroundStyle(.red)
                    Text("\(Int(s.activeCalories))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 10) {
                ActivityMetricRow(icon: "bolt.fill", color: .red,
                                  value: "\(Int(s.activeCalories)) kcal", label: "Calorie attive")
                ActivityMetricRow(icon: "fork.knife", color: .orange,
                                  value: "\(Int(s.calories)) kcal", label: "Calorie mangiate")
                ActivityMetricRow(icon: "figure.walk", color: .cyan,
                                  value: s.steps.formatted(), label: "Passi")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

struct ActivityMetricRow: View {
    let icon: String; let color: Color; let value: String; let label: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold()).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.bold())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

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

struct ActivityRectangularView: View {
    let s: DailySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Label("\(Int(s.activeCalories)) kcal", systemImage: "bolt.fill")
                    .foregroundStyle(.red)
                Label(s.steps.formatted(), systemImage: "figure.walk")
                    .foregroundStyle(.cyan)
            }
            .font(.headline)
            Label("\(Int(s.calories)) / \(Int(s.calorieGoal)) kcal mangiati",
                  systemImage: "fork.knife")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Shared: activity ring shape

struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let padding: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
                .padding(padding)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(padding)
        }
    }
}
