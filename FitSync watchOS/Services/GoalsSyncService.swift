import WatchConnectivity
import SwiftData
import FitSyncCore

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

    /// Applies any payload containing a "goals" key (or legacy top-level goals).
    private func handle(_ payload: [String: Any]) {
        guard let container, !payload.isEmpty else { return }
        let goalsDict: [String: Any]
        if let nested = payload["goals"] as? [String: Any] {
            goalsDict = nested
        } else if payload["dailyCalories"] != nil {
            goalsDict = payload                      // legacy top-level format
        } else {
            return
        }
        Task { @MainActor in
            let ctx = container.mainContext
            UserGoals.canonical(in: ctx).applySync(goalsDict)
            try? ctx.save()
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
