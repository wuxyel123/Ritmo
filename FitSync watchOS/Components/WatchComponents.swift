import SwiftUI
import WatchKit
import HealthKit
import FitSyncCore

// MARK: - Metric rows

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
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption).fontWeight(.semibold)
                Text("/ \(goal)").font(.caption2).foregroundStyle(.secondary)
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
                Text(emoji).font(.caption)
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(current)").font(.caption).fontWeight(.bold)
                        .foregroundStyle(isComplete ? .green : .primary)
                    Text("/ \(goal)\(unit)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isComplete ? Color.green : color)
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Sleep stage bar (compact, no legend)

struct WatchSleepStageBar: View {
    let session: SleepSession
    private var deepH:  Double { session.deepSleepHours }
    private var remH:   Double { session.remSleepHours }
    private var total:  Double { max(session.totalHours, 0.1) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2).fill(Color.indigo)
                    .frame(width: geo.size.width * CGFloat(deepH / total))
                RoundedRectangle(cornerRadius: 2).fill(Color.purple)
                    .frame(width: geo.size.width * CGFloat(remH / total))
                RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Logging helpers

struct WatchFeedback: Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct WatchSectionHeader: View {
    let icon: String
    let title: LocalizedStringKey
    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
            Text(title).font(.headline)
            Spacer()
        }
    }
}

struct WatchLogButton: View {
    let label: String
    let color: Color
    let action: () async -> Void
    var body: some View {
        Button { Task { await action() } } label: {
            Text(label)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

struct WatchToast: View {
    let feedback: WatchFeedback?
    var body: some View {
        if let fb = feedback {
            HStack(spacing: 6) {
                Image(systemName: fb.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(fb.isError ? .red : .green)
                Text(fb.message)
                    .font(.caption2).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(1)
        }
    }
}

// MARK: - Shared log helper

@MainActor
final class WatchLogHelper: ObservableObject {
    @Published var feedback: WatchFeedback?

    func log(_ success: String, action: () async throws -> Void) async {
        do {
            try await action()
            WKInterfaceDevice.current().play(.success)
            show(WatchFeedback(message: success, isError: false))
        } catch {
            let msg = hkAuthMessage(for: error) ?? error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
            show(WatchFeedback(message: msg, isError: true))
        }
    }

    private func show(_ fb: WatchFeedback) {
        feedback = fb
        Task {
            try? await Task.sleep(for: .seconds(3))
            if feedback?.id == fb.id { feedback = nil }
        }
    }
}

// MARK: - Free helpers

func hkAuthMessage(for error: Error) -> String? {
    guard let e = error as? HKError else { return nil }
    switch e.code {
    case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
        return "Vai su iPhone → Salute → Accesso app → FitSync"
    default: return nil
    }
}

func watchQualityColor(_ q: SleepQuality) -> Color {
    switch q {
    case .scarso:      return .red
    case .sufficiente: return .orange
    case .buono:       return .blue
    case .ottimo:      return .green
    }
}

func watchScoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return .green
    case 60..<80: return .yellow
    default:     return .orange
    }
}
