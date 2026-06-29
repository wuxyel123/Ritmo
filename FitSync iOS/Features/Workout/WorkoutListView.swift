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
                        ForEach(sessions) { session in
                            NavigationLink(destination: WorkoutDetailView(session: session)) {
                                if session.source == .healthKit {
                                    HealthKitWorkoutRow(session: session)
                                } else {
                                    WorkoutRow(session: session)
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
