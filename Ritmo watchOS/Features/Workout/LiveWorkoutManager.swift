import Foundation
import HealthKit
import SwiftUI

// MARK: - LiveWorkoutManager
//
// Wraps HKWorkoutSession + HKLiveWorkoutBuilder for tracking a workout live on
// the watch: elapsed time, heart rate and active calories while it runs, and
// the finished HKWorkout at the end (used to attach the RPE). The builder
// saves the workout to HealthKit itself — the app's normal import pipeline
// then picks it up like any other HealthKit workout on both devices.

@MainActor
final class LiveWorkoutManager: NSObject, ObservableObject {

    enum State { case idle, starting, running, paused, ended }

    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var finishedWorkout: HKWorkout?
    @Published var errorMessage: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?

    // MARK: Lifecycle

    func start(activity: HKWorkoutActivityType, isIndoor: Bool) async {
        guard state == .idle else { return }
        state = .starting

        // The builder needs share auth for the workout itself and for the
        // sample types it collects — requested here (not in the shared repo's
        // auth set) since only the live-workout flow needs write access to HR.
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling)
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate)
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = isIndoor ? .indoor : .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                         workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            state = .running
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    func togglePause() {
        switch state {
        case .running: session?.pause()
        case .paused:  session?.resume()
        default: break
        }
    }

    /// Ends the session; the finished HKWorkout arrives via the session
    /// delegate (state → .ended, `finishedWorkout` populated).
    func end() {
        session?.end()
    }

    func reset() {
        stopTimer()
        session = nil
        builder = nil
        state = .idle
        elapsed = 0
        heartRate = 0
        activeCalories = 0
        finishedWorkout = nil
        errorMessage = nil
    }

    // MARK: Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = self.builder?.elapsedTime ?? self.elapsed
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension LiveWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.state = .running
            case .paused:
                self.state = .paused
            case .ended:
                self.stopTimer()
                do {
                    try await self.builder?.endCollection(at: date)
                    self.finishedWorkout = try await self.builder?.finishWorkout()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
                self.state = .ended
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension LiveWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let kcal { self.activeCalories = kcal }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
