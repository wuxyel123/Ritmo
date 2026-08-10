import WatchConnectivity
import SwiftData
import RitmoCore

/// Pushes user goals + the excluded-workout set to the paired Apple Watch over
/// WatchConnectivity. Everything is tiny, so a single
/// application context carries the latest state, backed by transferUserInfo
/// (guaranteed delivery) and a live sendMessage when reachable.
final class GoalsSyncService: NSObject {
    static let shared = GoalsSyncService()

    private var latestGoals: [String: Any]?
    private var latestExcluded: [String]?
    private var latestTrainingLoad: Data?
    private var latestRecommendation: Data?
    private var latestMeetDate: Double?

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

    /// Push the iPhone-computed daily recommendation — the watch would reach
    /// a different verdict from its own store (no Hevy standalones, different
    /// import timing), so the phone's is the one displayed on both.
    func sendDailyRecommendation(_ recommendation: DailyRecommendation) {
        latestRecommendation = try? JSONEncoder().encode(recommendation)
        transmit()
    }

    /// Push the scheduled meet date (0 = cleared) for the watch complication.
    func sendMeetDate(_ epoch: Double) {
        latestMeetDate = epoch
        transmit()
    }

    /// Recompute-and-push in one step — the pattern every mutation site needs
    /// (delete, RPE change, import, manual log). One definition instead of a
    /// copy of the fetch in each view.
    @MainActor
    func sendTrainingLoad(recomputingFrom context: ModelContext) {
        let fresh = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        )) ?? []
        sendTrainingLoad(TrainingLoad.compute(from: fresh))
    }

    private func transmit() {
        let session = WCSession.default
        // Only activation is required; app context / transferUserInfo queue safely.
        guard session.activationState == .activated else { return }
        var payload: [String: Any] = [:]
        if let latestGoals { payload["goals"] = latestGoals }
        if let latestExcluded { payload["excludedWorkouts"] = latestExcluded }
        if let latestTrainingLoad { payload["trainingLoad"] = latestTrainingLoad }
        if let latestRecommendation { payload["dailyRecommendation"] = latestRecommendation }
        if let latestMeetDate { payload["meetDate"] = latestMeetDate }
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
