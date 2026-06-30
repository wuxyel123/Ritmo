import SwiftUI
import FitSyncCore

struct WatchMacroGoalsView: View {
    let goals: UserGoals
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Nutrizione")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                WatchGoalRow(emoji: "🔥", label: "Calorie",
                             current: Int(vm.snapshot.calories), goal: Int(vm.snapshot.calorieGoal),
                             unit: "kcal", color: .orange)
                WatchGoalRow(emoji: "🥩", label: "Proteine",
                             current: Int(vm.snapshot.protein), goal: Int(vm.snapshot.proteinGoal),
                             unit: "g", color: .red)
                WatchGoalRow(emoji: "🍞", label: "Carboidrati",
                             current: Int(vm.snapshot.carbs), goal: Int(vm.snapshot.carbsGoal),
                             unit: "g", color: .yellow)
                WatchGoalRow(emoji: "🥑", label: "Grassi",
                             current: Int(vm.snapshot.fat), goal: Int(vm.snapshot.fatGoal),
                             unit: "g", color: .green)
                WatchGoalRow(emoji: "🌾", label: "Fibre",
                             current: Int(vm.snapshot.fiber), goal: Int(vm.snapshot.fiberGoal),
                             unit: "g", color: .mint)
                WatchGoalRowDecimal(emoji: "💧", label: "Acqua",
                                    current: vm.snapshot.waterMl / 1000, goal: vm.snapshot.waterGoal / 1000,
                                    unit: "L", color: .blue)
            }
            .padding(.horizontal, 8)
        }
    }
}
