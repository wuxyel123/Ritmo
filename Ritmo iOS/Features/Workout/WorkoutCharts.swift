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
                    // 36pt fitted "41s" but not "64m44s", which wrapped and
                    // hyphenated into "64-" / "m44s" on a long zone-1 walk.
                    Text(secs > 0 ? formatTime(secs) : "—")
                        .font(.caption2.bold()).foregroundStyle(color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    /// Past an hour, "64m44s" is both long and hard to read — use "1h 4m".
    private func formatTime(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return sec > 0 ? "\(m)m\(sec)s" : "\(m)m" }
        return "\(sec)s"
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
