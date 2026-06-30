import SwiftUI
import FitSyncCore

struct WatchWorkoutView: View {
    let goals: UserGoals
    let sessions: [WorkoutSession]
    @EnvironmentObject private var vm: WatchViewModel

    private var todaySessions: [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return sessions.filter { $0.startTime >= start && $0.startTime < end }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Allenamento")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if todaySessions.isEmpty && !vm.snapshot.hasWorkedOutToday {
                    VStack(spacing: 6) {
                        Text("💤").font(.system(size: 32))
                        Text("Nessun allenamento oggi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                } else {
                    ForEach(todaySessions) { session in
                        WatchWorkoutRow(session: session)
                    }
                    if todaySessions.isEmpty && vm.snapshot.hasWorkedOutToday {
                        VStack(spacing: 4) {
                            Text("✅").font(.system(size: 28))
                            Text("Allenamento completato")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if !sessions.isEmpty && todaySessions.isEmpty {
                    Divider()
                    Text("Ultimo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let last = sessions.first {
                        WatchWorkoutRow(session: last)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

struct WatchWorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text("\(session.durationMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(session.startTime, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.totalVolumeKg > 0 {
                    Text("\(Int(session.totalVolumeKg / 1000))k kg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(6)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
