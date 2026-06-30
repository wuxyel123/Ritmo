import SwiftUI
import FitSyncCore

struct WatchHealthView: View {
    @EnvironmentObject private var vm: WatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
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

    private func healthMetric(
        _ icon: String, _ label: String,
        _ value: String, _ unit: String,
        _ color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 2) {
                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(value == "--" ? .secondary : color)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
