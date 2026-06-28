import SwiftUI
import SwiftData
import FitSyncCore

// MARK: - Watch App Entry Point
@main
struct FitSyncWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTabView()
                .modelContainer(FitSyncStore.container)
        }
    }
}

// MARK: - Tab Root
struct WatchTabView: View {
    var body: some View {
        TabView {
            WatchDashboardView()
            WatchMacroGoalsView()
            WatchWorkoutView()
        }
        #if os(watchOS)
        .tabViewStyle(.page)
        #endif
    }
}

// MARK: - Dashboard (Score + Passi + Sonno)
struct WatchDashboardView: View {
    @StateObject private var vm = WatchViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Score giornaliero
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Score oggi")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(vm.snapshot.dayScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor(vm.snapshot.dayScore))
                        Text("su 100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(vm.snapshot.dayScore) / 100)
                            .stroke(scoreColor(vm.snapshot.dayScore), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(vm.snapshot.hasWorkedOutToday ? "💪" : "🛋️")
                            .font(.title3)
                    }
                    .frame(width: 52, height: 52)
                }
                .padding(.horizontal, 4)

                Divider()

                // Passi
                WatchMetricRow(
                    icon: "🚶",
                    label: "Passi",
                    value: "\(vm.snapshot.steps.formatted())",
                    goal: "\(vm.snapshot.stepGoal.formatted())",
                    progress: Double(vm.snapshot.steps) / Double(max(vm.snapshot.stepGoal, 1))
                )

                // Sonno
                WatchMetricRow(
                    icon: "😴",
                    label: "Sonno",
                    value: String(format: "%.1fh", vm.snapshot.sleepHours),
                    goal: "8.0h",
                    progress: vm.snapshot.sleepHours / 8.0
                )

                // Calorie attive
                WatchMetricRow(
                    icon: "🔥",
                    label: "Kcal attive",
                    value: "\(Int(vm.snapshot.activeCalories))",
                    goal: "400",
                    progress: vm.snapshot.activeCalories / 400
                )
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("FitSync")
        .task { await vm.load() }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }
}

// MARK: - Macro Goals View (la più importante su Watch)
struct WatchMacroGoalsView: View {
    @StateObject private var vm = WatchViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Obiettivi oggi")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Calorie
                WatchGoalRow(
                    emoji: "🔥",
                    label: "Calorie",
                    current: Int(vm.snapshot.calories),
                    goal: Int(vm.snapshot.calorieGoal),
                    unit: "kcal",
                    color: .orange
                )

                // Proteine
                WatchGoalRow(
                    emoji: "🥩",
                    label: "Proteine",
                    current: Int(vm.snapshot.protein),
                    goal: Int(vm.snapshot.proteinGoal),
                    unit: "g",
                    color: .red
                )

                // Carbs
                WatchGoalRow(
                    emoji: "🍞",
                    label: "Carboidrati",
                    current: Int(vm.snapshot.carbs),
                    goal: Int(vm.snapshot.carbsGoal),
                    unit: "g",
                    color: .yellow
                )

                // Grassi
                WatchGoalRow(
                    emoji: "🥑",
                    label: "Grassi",
                    current: Int(vm.snapshot.fat),
                    goal: Int(vm.snapshot.fatGoal),
                    unit: "g",
                    color: .green
                )

                // Fibre
                WatchGoalRow(
                    emoji: "🌾",
                    label: "Fibre",
                    current: Int(vm.snapshot.fiber),
                    goal: Int(vm.snapshot.fiberGoal),
                    unit: "g",
                    color: .mint
                )

                // Acqua
                WatchGoalRow(
                    emoji: "💧",
                    label: "Acqua",
                    current: Int(vm.snapshot.waterMl / 100),
                    goal: Int(vm.snapshot.waterGoal / 100),
                    unit: "dl",
                    color: .blue
                )
            }
            .padding(.horizontal, 8)
        }
        .task { await vm.load() }
    }
}

// MARK: - Workout rapido Watch
struct WatchWorkoutView: View {
    @StateObject private var vm = WatchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            Text("Allenamento")
                .font(.headline)

            if vm.snapshot.hasWorkedOutToday {
                VStack(spacing: 4) {
                    Text("✅")
                        .font(.system(size: 36))
                    Text("Completato oggi!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(spacing: 4) {
                    Text("💤")
                        .font(.system(size: 36))
                    Text("Nessun allenamento")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Text("Apri FitSync su iPhone per i dettagli")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .task { await vm.load() }
    }
}

// MARK: - Reusable Watch Components

struct WatchMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let goal: String
    let progress: Double

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(icon)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("/ \(goal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress, 1.0))
                .tint(progress >= 1 ? .green : .blue)
                .scaleEffect(x: 1, y: 1.5)
        }
    }
}

struct WatchGoalRow: View {
    let emoji: String
    let label: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(current) / Double(goal), 1.0)
    }

    private var isComplete: Bool { current >= goal }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(current)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(isComplete ? .green : .primary)
                    Text("/ \(goal)\(unit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isComplete ? Color.green : color)
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Watch ViewModel
@MainActor
final class WatchViewModel: ObservableObject {
    @Published var snapshot: DailySnapshot = .placeholder

    private let healthRepo = HealthKitRepository()

    func load() async {
        await healthRepo.requestAuthorization()
        // In produzione: legge da App Group UserDefaults (condiviso con iOS)
        // oppure via WatchConnectivity. Per ora usa il repository diretto.
        // Su Watch il HealthKit ha accesso diretto ai dati.
        let goals = UserGoals() // Idealmente fetchato da SwiftData
        snapshot = await healthRepo.fetchDailySnapshot(goals: goals)
    }
}
