import WatchConnectivity
import FitSyncCore

/// Pushes user goals to the paired Apple Watch over WatchConnectivity (the watch
/// has no CloudKit). Goals are tiny, so every channel is used for reliability:
///  - `updateApplicationContext` — latest-state, pulled on watch activation.
///  - `transferUserInfo` — guaranteed queued delivery.
///  - `sendMessage` — instant, when reachable.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    private var latestGoals: [String: Any]?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ goals: UserGoals) {
        latestGoals = goals.syncPayload
        transmitGoals()
    }

    private func transmitGoals() {
        let session = WCSession.default
        // Only activation is required: updateApplicationContext and transferUserInfo
        // queue safely regardless of momentary isPaired/isWatchAppInstalled state.
        guard let payload = latestGoals, session.activationState == .activated else { return }
        try? session.updateApplicationContext(["goals": payload])
        session.transferUserInfo(["goals": payload])
        if session.isReachable {
            session.sendMessage(["goals": payload], replyHandler: nil, errorHandler: nil)
        }
    }
}

extension GoalsSyncService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async { self.transmitGoals() }
    }

    // Re-push goals whenever the Watch becomes reachable (e.g. wrist raised)
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.transmitGoals() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
