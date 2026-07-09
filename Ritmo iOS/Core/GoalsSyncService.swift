import WatchConnectivity
import RitmoCore

/// Pushes user goals + the excluded-workout set to the paired Apple Watch over
/// WatchConnectivity (the watch has no CloudKit). Everything is tiny, so a single
/// application context carries the latest state, backed by transferUserInfo
/// (guaranteed delivery) and a live sendMessage when reachable.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    private var latestGoals: [String: Any]?
    private var latestExcluded: [String]?
    private var latestTrainingLoad: Data?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ goals: UserGoals) {
        latestGoals = goals.syncPayload
        transmit()
    }

    /// Push the current excluded-workout set so an iPhone deletion reflects on the watch.
    func sendExcludedWorkouts(_ uuids: [String]) {
        latestExcluded = uuids
        transmit()
    }

    /// Push the iPhone-computed training load so the Watch displays the SAME
    /// number instead of recomputing from its own (independently imported,
    /// possibly briefly out of sync) local workout list.
    func sendTrainingLoad(_ load: TrainingLoad) {
        latestTrainingLoad = try? JSONEncoder().encode(load)
        transmit()
    }

    private func transmit() {
        let session = WCSession.default
        // Only activation is required; app context / transferUserInfo queue safely.
        guard session.activationState == .activated else { return }
        var payload: [String: Any] = [:]
        if let latestGoals { payload["goals"] = latestGoals }
        if let latestExcluded { payload["excludedWorkouts"] = latestExcluded }
        if let latestTrainingLoad { payload["trainingLoad"] = latestTrainingLoad }
        guard !payload.isEmpty else { return }
        try? session.updateApplicationContext(payload)
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension GoalsSyncService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async { self.transmit() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
