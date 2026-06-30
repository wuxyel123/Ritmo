import SwiftUI
import FitSyncCore

// Single "home" tab that combines the old score + the old recovery breakdown.
struct WatchHomeView: View {
    let goals: UserGoals
    let sessions: [WorkoutSession]
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {

                // ── Score ring + label ──────────────────────────────────────
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(vm.snapshot.dayScore) / 100)
                            .stroke(scoreColor(vm.snapshot.dayScore),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(vm.snapshot.hasWorkedOutToday ? "💪" : "🛋️")
                            .font(.title3)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Score oggi")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(vm.snapshot.dayScore)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor(vm.snapshot.dayScore))
                        Text("su 100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                Divider()

                // ── Activity metrics ────────────────────────────────────────
                WatchMetricRow(
                    icon: "🚶", label: "Passi",
                    value: "\(vm.snapshot.steps.formatted())",
                    goal: "\(vm.snapshot.stepGoal.formatted())",
                    progress: Double(vm.snapshot.steps) / Double(max(vm.snapshot.stepGoal, 1))
                )
                WatchMetricRow(
                    icon: "😴", label: "Sonno",
                    value: String(format: "%.1fh", vm.snapshot.sleepHours),
                    goal: "8.0h",
                    progress: vm.snapshot.sleepHours / 8.0
                )
                WatchMetricRow(
                    icon: "🔥", label: "Kcal attive",
                    value: "\(Int(vm.snapshot.activeCalories))",
                    goal: "\(Int(vm.snapshot.activeCalorieGoal))",
                    progress: vm.snapshot.activeCalories / max(vm.snapshot.activeCalorieGoal, 1)
                )

                Divider()

                // ── Score breakdown ─────────────────────────────────────────
                scoreRow("Recupero",   vm.snapshot.recoveryScore,  30, .indigo)
                scoreRow("Movimento",  vm.snapshot.movementScore,  40, .green)
                scoreRow("Nutrizione", vm.snapshot.nutritionScore, 20, .orange)
                scoreRow("Workout",    vm.snapshot.workoutBonus,   10, .purple)

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("FitSync")
    }

    // MARK: Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    private func scoreRow(_ label: String, _ value: Double, _ max: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 10)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: geo.size.width * CGFloat(min(value / max, 1.0)), height: 4)
                }
            }
            .frame(height: 4)
            Text("\(Int(value))/\(Int(max))").font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 14)
    }
}
