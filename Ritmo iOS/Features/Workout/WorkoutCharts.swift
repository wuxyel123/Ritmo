import SwiftUI
import Charts
import RitmoCore

struct HRZonesChart: View {
    let zones: HRZones

    private var zoneData: [(String, Double, Color, String)] {
        [
            ("Z1 Recovery",  zones.z1, Color.blue,   "<60%"),
            ("Z2 Brucia ♥", zones.z2, Color.green,  "60-70%"),
            ("Z3 Aerobico",  zones.z3, Color.yellow, "70-80%"),
            ("Z4 Soglia",    zones.z4, Color.orange, "80-90%"),
            ("Z5 Peak",      zones.z5, Color.red,    ">90%")
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(zoneData, id: \.0) { name, secs, color, range in
                let fraction = zones.total > 0 ? secs / zones.total : 0
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(name)).font(.caption2).frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)).frame(height: 18)
                            RoundedRectangle(cornerRadius: 4).fill(color)
                                .frame(width: geo.size.width * fraction, height: 18)
                        }
                    }
                    .frame(height: 18)
                    Text(secs > 0 ? formatTime(secs) : "—")
                        .font(.caption2.bold()).foregroundStyle(color).frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return m > 0 ? "\(m)m\(sec > 0 ? "\(sec)s" : "")" : "\(sec)s"
    }
}

struct HeartStatItem: View {
    let value: String; let label: LocalizedStringKey; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared workout styling
//
// One definition each — these switches were previously copied per view and
// had already drifted apart (warmup was orange in one screen, blue in another).

/// Color for a training-load status, used by the load card, the load detail
/// and the per-workout load context.
func loadStatusColor(_ status: TrainingLoadStatus) -> Color {
    switch status {
    case .low:      return .blue
    case .optimal:  return .green
    case .high:     return .orange
    case .veryHigh: return .red
    }
}

/// Color for a set type (editor chips + detail table).
func setTypeColor(_ type: SetType) -> Color {
    switch type {
    case .normal:  return RitmoTheme.textSecondary
    case .warmup:  return .orange
    case .dropSet: return .purple
    case .failure: return .red
    }
}

/// One-letter label for a set type (Riscaldamento → R, Cedimento → C…).
func setTypeShortLabel(_ type: SetType) -> String {
    switch type {
    case .normal:  return "N"
    case .warmup:  return "R"
    case .dropSet: return "D"
    case .failure: return "C"
    }
}

struct StatItem: View {
    let value: String; let label: LocalizedStringKey; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
