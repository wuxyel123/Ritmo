import SwiftUI
import SwiftData
import FitSyncCore

struct WorkoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthRepo: HealthKitRepository
    @Query(sort: \WorkoutSession.startTime, order: .reverse) private var sessions: [WorkoutSession]
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyWorkoutView(onSync: { Task { await syncHealthKit() } })
                } else {
                    List {
                        TrainingLoadCard(load: TrainingLoad.compute(from: sessions))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                        ForEach(sessions) { session in
                            NavigationLink(destination: WorkoutDetailView(session: session)) {
                                if session.source == .healthKit {
                                    HealthKitWorkoutRow(session: session)
                                } else {
                                    WorkoutRow(session: session)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    healthRepo.deleteWorkout(session, in: modelContext)
                                } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Allenamenti")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { Task { await syncHealthKit() } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .task { await syncHealthKit() }
            .refreshable { await syncHealthKit() }
        }
    }

    private func syncHealthKit() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await healthRepo.importHealthKitWorkouts(into: modelContext)
    }
}

// MARK: - Training Load Card

struct TrainingLoadCard: View {
    let load: TrainingLoad

    private var color: Color {
        switch load.status {
        case .low:      return .blue
        case .optimal:  return .green
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }

    var body: some View {
        FitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Carico allenamento")
                    Spacer()
                    Text(LocalizedStringKey(load.status.label))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(load.acute)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text("carico 7 giorni").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("media \(load.chronic)").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    let maxV = max(load.weeklyEfforts.max() ?? 1, 1)
                    ForEach(Array(load.weeklyEfforts.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(v > 0 ? color : Color.gray.opacity(0.2))
                            .frame(height: max(4, CGFloat(v) / CGFloat(maxV) * 34))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 34)
            }
        }
    }
}
