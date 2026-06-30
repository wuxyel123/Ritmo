import WatchConnectivity
import SwiftData
import FitSyncCore

extension Notification.Name {
    static let goalsSyncDidUpdate = Notification.Name("goalsSyncDidUpdate")
}

/// Receives UserGoals pushed from the paired iPhone and writes them into SwiftData.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    var container: ModelContainer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ payload: [String: Any]) {
        guard let container else { return }
        Task { @MainActor in
            let ctx = container.mainContext
            let goals: UserGoals
            if let existing = try? ctx.fetch(FetchDescriptor<UserGoals>()).first {
                goals = existing
            } else {
                goals = UserGoals()
                ctx.insert(goals)
            }
            goals.applySync(payload)
            try? ctx.save()
            // Notify WatchTabView so it immediately reloads vm.snapshot with the new goals.
            NotificationCenter.default.post(name: .goalsSyncDidUpdate, object: nil)
        }
    }
}

extension GoalsSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        apply(userInfo)
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}
}
