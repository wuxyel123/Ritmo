import SwiftUI
import RitmoCore

struct WatchWaterView: View {
    let goals: UserGoals
    let sessions: [WorkoutSession]

    @EnvironmentObject private var vm: WatchViewModel
    @StateObject private var helper = WatchLogHelper()
    @StateObject private var healthRepo = HealthKitRepository()

    private let presets: [(String, Double)] = [
        ("150 ml", 150), ("200 ml", 200), ("330 ml", 330), ("500 ml", 500)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 12) {
                    WatchSectionHeader(icon: "💧", title: "Acqua")

                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill").foregroundStyle(.blue).font(.caption)
                        Text("\(Int(vm.snapshot.waterMl)) ml")
                            .font(.caption.bold())
                        Text("/ \(Int(vm.snapshot.waterGoal)) ml")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(presets, id: \.0) { label, ml in
                            WatchLogButton(label: label, color: .blue) {
                                await helper.log("Acqua aggiunta!") {
                                    try await healthRepo.writeWater(ml: ml)
                                }
                                await vm.load(goals: goals)
                            }
                        }
                    }

                    Color.clear.frame(height: 36)
                }
                .padding(.horizontal, 8)
            }

            WatchToast(feedback: helper.feedback)
        }
        .task { await healthRepo.requestAuthorization() }
        .animation(.spring(duration: 0.3), value: helper.feedback?.id)
    }
}
