import SwiftUI
import RitmoCore

struct WatchRecoveryView: View {
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                scoreHeader
                Divider().padding(.vertical, 2)
                scoreBreakdown
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Recupero")
    }

    // MARK: Score header (day score ring)

    private var scoreHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(vm.snapshot.dayScore) / 100)
                    .stroke(watchScoreColor(vm.snapshot.dayScore),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(vm.snapshot.dayScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(watchScoreColor(vm.snapshot.dayScore))
                    Text("/100").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Score oggi").font(.caption2).foregroundStyle(.secondary)
                Text(scoreLabel(vm.snapshot.dayScore))
                    .font(.caption.bold())
                    .foregroundStyle(watchScoreColor(vm.snapshot.dayScore))
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Score breakdown

    private var scoreBreakdown: some View {
        VStack(spacing: 5) {
            scoreRow("Recupero",   vm.snapshot.recoveryScore,  30, .indigo)
            scoreRow("Movimento",  vm.snapshot.movementScore,  40, .green)
            scoreRow("Nutrizione", vm.snapshot.nutritionScore, 20, .orange)
            scoreRow("Workout",    vm.snapshot.workoutBonus,   10, .purple)
        }
    }

    // MARK: Sub-views

    private func scoreRow(_ label: String, _ value: Double, _ max: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: 4, height: 10)
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

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...100: return "Ottimo"
        case 60..<80:  return "Buono"
        case 40..<60:  return "Sufficiente"
        default:       return "Da migliorare"
        }
    }
}
