import SwiftUI
import HealthKit
import RitmoCore

struct WorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(session.title)).font(.headline)
                Spacer()
                SourceBadge(source: session.source, appName: session.sourceAppName)
            }
            Text(session.startTime, format: .dateTime.day().month().year())
                .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
            HStack(spacing: 16) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                Label("\(session.sets.count) serie", systemImage: "list.bullet")
                if session.totalVolumeKg > 0 {
                    Label("\(Int(session.totalVolumeKg / 1000))k kg", systemImage: "scalemass")
                }
                Label("RPE \(session.effortScore)", systemImage: "gauge.with.dots.needle.50percent")
            }
            .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
            if !session.muscleGroups.isEmpty {
                HStack(spacing: 6) {
                    ForEach(session.muscleGroups.prefix(3), id: \.self) { group in
                        Text(LocalizedStringKey(group.rawValue))
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RitmoTheme.workout.opacity(0.12), in: Capsule())
                            .foregroundStyle(RitmoTheme.workout)
                    }
                    if session.muscleGroups.count > 3 {
                        Text("+\(session.muscleGroups.count - 3)")
                            .font(.caption2).foregroundStyle(RitmoTheme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HealthKitWorkoutRow: View {
    let session: WorkoutSession

    var activitySymbol: String {
        HKWorkoutActivityType(rawValue: UInt(session.hkActivityType))?.ritmoActivitySymbol
            ?? "figure.mixed.cardio"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(LocalizedStringKey(session.title), systemImage: activitySymbol).font(.headline)
                Spacer()
                SourceBadge(source: .healthKit, appName: session.sourceAppName)
            }
            Text(session.startTime, format: .dateTime.day().month().year())
                .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
            HStack(spacing: 16) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                if session.activeCalories > 0 {
                    Label("\(Int(session.activeCalories)) kcal", systemImage: "bolt.fill")
                        .foregroundStyle(.red)
                }
                if session.distanceMeters > 100 {
                    Label(formattedDistance, systemImage: "arrow.forward")
                        .foregroundStyle(.cyan)
                }
                Label("RPE \(session.effortScore)", systemImage: "gauge.with.dots.needle.50percent")
            }
            .font(.caption).foregroundStyle(RitmoTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String {
        session.distanceMeters >= 1000
            ? String(format: "%.2f km", session.distanceMeters / 1000)
            : String(format: "%.0f m", session.distanceMeters)
    }
}

struct SourceBadge: View {
    let source: DataSource
    /// Recording app from HealthKit's source revision (e.g. "Hevy", "WHOOP",
    /// the watch's name) — Fitness-style attribution. Real third-party app
    /// icons aren't accessible via public API, so name + glyph it is.
    var appName: String? = nil

    private var isWatch: Bool {
        appName.map { $0.localizedCaseInsensitiveContains("watch") } ?? false
    }

    var color: Color {
        if appName != nil { return source == .healthKit ? .red : .blue }
        switch source {
        case .healthKit: return .red
        case .manual:    return .gray
        case .hevy:      return .blue
        }
    }
    var icon: String {
        if isWatch { return "applewatch" }
        switch source {
        case .healthKit: return appName == nil ? "heart.fill" : "app.badge.fill"
        case .manual:    return "pencil.circle.fill"
        case .hevy:      return "square.and.arrow.down.fill"
        }
    }
    var body: some View {
        Label(LocalizedStringKey(appName ?? source.rawValue), systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct EmptyWorkoutView: View {
    let onSync: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "dumbbell")
                .font(.system(size: 64))
                .foregroundStyle(RitmoTheme.workout.opacity(0.5))
            VStack(spacing: 8) {
                Text("Nessun allenamento")
                    .font(.title3.bold())
                Text("I tuoi allenamenti Apple Fitness appaiono qui automaticamente.")
                    .font(.subheadline)
                    .foregroundStyle(RitmoTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onSync) {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text("Sincronizza ora").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(RitmoTheme.cardPadding)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: RitmoTheme.cardRadius))
            }
        }
        .padding(RitmoTheme.pagePadding)
    }
}
