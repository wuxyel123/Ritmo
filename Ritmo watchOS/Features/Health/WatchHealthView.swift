import SwiftUI
import RitmoCore

struct WatchHealthView: View {
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {

                if let r = vm.recovery {
                    recoveryCard(r)
                    Divider().padding(.vertical, 2)
                }

                WatchSectionHeader(icon: "❤️", title: "Salute")

                healthMetric("heart.fill",          "FC riposo",
                             vm.activity.heartRateResting.map { "\(Int($0))" } ?? "--",
                             "bpm", .red)
                healthMetric("waveform.path.ecg",   "HRV",
                             vm.activity.hrv.map { "\(Int($0))" } ?? "--",
                             "ms", .green)
                healthMetric("drop.fill",           "SpO₂",
                             vm.activity.spO2.map { String(format: "%.0f", $0) } ?? "--",
                             "%", .cyan)

                if let vo2 = vm.activity.vo2Max {
                    healthMetric("lungs.fill", "VO₂ Max",
                                 String(format: "%.0f", vo2),
                                 "ml/kg/min", .blue)
                }

                if let rr = vm.activity.respiratoryRate {
                    healthMetric("wind", "Respiro",
                                 String(format: "%.0f", rr),
                                 "atti/min", .teal)
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 8)
        }
    }

    private func recoveryColor(_ status: RecoveryStatus) -> Color {
        switch status {
        case .poor:      return .red
        case .fair:      return .orange
        case .good:      return .yellow
        case .excellent: return .green
        }
    }

    @ViewBuilder
    private func recoveryCard(_ r: RecoveryScore) -> some View {
        let color = recoveryColor(r.status)
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(r.overall) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(r.overall)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recupero").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(LocalizedStringKey(r.status.label))
                    .font(.caption.bold()).foregroundStyle(color)
                Text(r.hasHeartData ? LocalizedStringKey("Sonno · HRV · FC")
                                    : LocalizedStringKey("Solo sonno"))
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func healthMetric(
        _ icon: String, _ label: String,
        _ value: String, _ unit: String,
        _ color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(color)
                .frame(width: 14)
            Text(LocalizedStringKey(label))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 2) {
                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(value == "--" ? .secondary : color)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
