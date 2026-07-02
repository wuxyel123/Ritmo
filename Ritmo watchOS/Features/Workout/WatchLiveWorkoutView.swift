import SwiftUI
import HealthKit
import RitmoCore

// MARK: - WatchLiveWorkoutView
//
// Full live-workout flow: activity picker → live metrics (timer, HR, kcal,
// pause/end) → RPE prompt at the end. The finished workout is saved to
// HealthKit by the builder; the RPE is attached via the same effort-score API
// used everywhere else, then the watch store re-imports so the session appears
// immediately in the workout tab (and on the iPhone at its next import).

struct WatchLiveWorkoutView: View {
    @StateObject private var manager = LiveWorkoutManager()
    @Environment(\.dismiss) private var dismiss
    var onFinished: (() -> Void)? = nil

    var body: some View {
        Group {
            switch manager.state {
            case .idle, .starting:
                ActivityPickerView(isStarting: manager.state == .starting) { activity, indoor in
                    Task { await manager.start(activity: activity, isIndoor: indoor) }
                }
            case .running, .paused:
                liveView
            case .ended:
                RPESaveView(workout: manager.finishedWorkout) {
                    onFinished?()
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(manager.state == .running || manager.state == .paused)
    }

    // MARK: Live metrics

    private var liveView: some View {
        VStack(spacing: 10) {
            Text(timeString(manager.elapsed))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(manager.state == .paused ? .yellow : .green)

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(manager.heartRate > 0 ? "\(Int(manager.heartRate))" : "--")
                        .font(.title3.bold()).monospacedDigit()
                }
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(Int(manager.activeCalories))")
                        .font(.title3.bold()).monospacedDigit()
                }
            }

            if manager.state == .paused {
                Text("In pausa").font(.caption2).foregroundStyle(.yellow)
            }

            HStack(spacing: 10) {
                Button {
                    manager.togglePause()
                } label: {
                    Image(systemName: manager.state == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.yellow)

                Button {
                    manager.end()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(Color.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.red)
            }

            if let error = manager.errorMessage {
                Text(error).font(.system(size: 9)).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - ActivityPickerView

private struct ActivityPickerView: View {
    let isStarting: Bool
    let onPick: (HKWorkoutActivityType, Bool) -> Void

    private let activities: [(emoji: String, name: String, type: HKWorkoutActivityType, indoor: Bool)] = [
        ("🏋️", "Forza",            .traditionalStrengthTraining, true),
        ("💪", "Forza funzionale", .functionalStrengthTraining,  true),
        ("🏃", "Corsa",            .running,                     false),
        ("🚶", "Camminata",        .walking,                     false),
        ("🚴", "Ciclismo",         .cycling,                     false),
        ("🔥", "HIIT",             .highIntensityIntervalTraining, true),
        ("🧘", "Yoga",             .yoga,                        true),
        ("⚙️", "Altro",            .other,                       true)
    ]

    var body: some View {
        if isStarting {
            ProgressView("Avvio…")
        } else {
            List {
                ForEach(activities, id: \.name) { activity in
                    Button {
                        onPick(activity.type, activity.indoor)
                    } label: {
                        HStack(spacing: 8) {
                            Text(activity.emoji)
                            Text(LocalizedStringKey(activity.name)).font(.system(size: 14))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Allenamento")
        }
    }
}

// MARK: - RPESaveView

private struct RPESaveView: View {
    let workout: HKWorkout?
    let onDone: () -> Void

    @State private var rpe = 7
    @State private var isSaving = false
    private let healthRepo = HealthKitRepository()

    var body: some View {
        VStack(spacing: 10) {
            Text("Com'è andata?")
                .font(.headline)
            Text("RPE — sforzo percepito")
                .font(.caption2).foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button { if rpe > 1 { rpe -= 1 } } label: {
                    Image(systemName: "minus").frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.gray.opacity(0.2), in: Circle())

                Text("\(rpe)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(rpeColor)
                    .frame(width: 50)

                Button { if rpe < 10 { rpe += 1 } } label: {
                    Image(systemName: "plus").frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.gray.opacity(0.2), in: Circle())
            }

            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                } else {
                    Text("Salva")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)
            .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.green)
            .disabled(isSaving)

            Button("Salta") { finish(withRPE: false) }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var rpeColor: Color {
        switch rpe {
        case ..<4:  return .green
        case ..<7:  return .yellow
        case ..<9:  return .orange
        default:    return .red
        }
    }

    private func save() {
        isSaving = true
        finish(withRPE: true)
    }

    private func finish(withRPE: Bool) {
        Task { @MainActor in
            if withRPE, let workout {
                await healthRepo.saveWorkoutEffort(rpe: rpe, forWorkoutUUID: workout.uuid.uuidString)
            }
            // Pull the new workout into the watch's own store right away.
            await healthRepo.importHealthKitWorkouts(into: RitmoStore.container.mainContext)
            onDone()
        }
    }
}
