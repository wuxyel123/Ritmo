import WatchConnectivity
import FitSyncCore

/// Pushes UserGoals to the paired Apple Watch via WatchConnectivity.
/// Buffers the payload if WCSession isn't activated yet and flushes
/// automatically once activation completes.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    private var pendingPayload: [String: Any]?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ goals: UserGoals) {
        guard WCSession.isSupported() else { return }
        let payload = goals.syncPayload
        pendingPayload = payload
        guard WCSession.default.activationState == .activated else {
            // Will be flushed in activationDidCompleteWith
            return
        }
        transmit(payload)
    }

    private func transmit(_ payload: [String: Any]) {
        let session = WCSession.default
        guard session.isPaired, session.isWatchAppInstalled else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        session.transferUserInfo(payload)
    }
}

extension GoalsSyncService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated, let payload = pendingPayload else { return }
        pendingPayload = nil
        DispatchQueue.main.async { self.transmit(payload) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
