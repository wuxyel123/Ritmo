import WatchConnectivity
import SwiftData
import WidgetKit
import RitmoCore

extension Notification.Name {
    static let goalsSyncDidUpdate = Notification.Name("goalsSyncDidUpdate")
}

/// Receives user goals pushed from the paired iPhone and writes them into the
/// watch's SwiftData store (which has no CloudKit). Workouts come from HealthKit.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    var container: ModelContainer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Applies goals, the excluded-workout set, and/or the training load from the iPhone.
    private func handle(_ payload: [String: Any]) {
        guard let container, !payload.isEmpty else { return }

        // Excluded workouts: mirror the iPhone's set so its deletions reflect here.
        if let excluded = payload["excludedWorkouts"] as? [String] {
            HealthKitRepository.replaceExcludedWorkoutUUIDs(excluded)
        }

        // Training load: iPhone is the source of truth, cache it so the Watch
        // shows the same number instead of recomputing from its own local import.
        if let data = payload["trainingLoad"] as? Data {
            HealthKitRepository.cacheTrainingLoad(data)
        }

        // Daily recommendation: same rationale — the phone's verdict is the
        // one displayed on both devices (day-checked at render time).
        if let data = payload["dailyRecommendation"] as? Data {
            HealthKitRepository.cacheDailyRecommendation(data)
        }

        // Scheduled meet date → countdown complication.
        if let meetEpoch = payload["meetDate"] as? Double {
            HealthKitRepository.cacheMeetDate(meetEpoch)
            WidgetCenter.shared.reloadTimelines(ofKind: "RitmoMeetCountdown")
        }

        let goalsDict: [String: Any]?
        if let nested = payload["goals"] as? [String: Any] {
            goalsDict = nested
        } else if payload["dailyCalories"] != nil {
            goalsDict = payload                      // legacy top-level format
        } else {
            goalsDict = nil
        }
        guard goalsDict != nil || payload["excludedWorkouts"] != nil
                || payload["trainingLoad"] != nil || payload["dailyRecommendation"] != nil else { return }

        Task { @MainActor in
            let ctx = container.mainContext
            if let goalsDict { UserGoals.canonical(in: ctx).applySync(goalsDict) }
            try? ctx.save()
            // Triggers WatchTabView.reload → import reconciles (prunes excluded workouts).
            NotificationCenter.default.post(name: .goalsSyncDidUpdate, object: nil)
        }
    }
}

extension GoalsSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // Pull whatever the phone last set, so a standalone watch launch is covered.
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { handle(ctx) }
    }
}
