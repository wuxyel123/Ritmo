import Foundation

// MARK: - Workout effort & training load
//
// Apple-style training load: recent (7-day) load vs a 28-day baseline.
// Per-workout effort is a 1–10 RPE-like score. Strength work (powerlifting etc.)
// sits in HR zone 1 yet is high-intensity, so calories under-rate it — we score
// strength by duration, and cardio by calorie intensity.

public enum WorkoutCategory {
    case strength, cardio, other

    public var displayName: String {
        switch self {
        case .strength: return "Forza"
        case .cardio:   return "Cardio"
        case .other:    return "Altro"
        }
    }
}

extension WorkoutSession {
    /// HKWorkoutActivityType raw values for gym/strength work.
    private static let strengthActivityTypes: Set<Int> = [
        50, // traditionalStrengthTraining
        20, // functionalStrengthTraining
        79  // coreTraining
    ]

    public var category: WorkoutCategory {
        if Self.strengthActivityTypes.contains(hkActivityType) { return .strength }
        return activeCalories > 0 ? .cardio : .other
    }

    /// Auto-estimated effort, 1–10 (RPE-like), from duration/calories.
    public var autoEffort: Int {
        let minutes = max(Double(durationMinutes), 1)
        switch category {
        case .strength:
            // Duration-driven: a long, hard lifting session ≈ 90 min → 10.
            return clampEffort(minutes / 9.0)
        case .cardio:
            // Intensity-driven: kcal/min, ~14 kcal/min → 10.
            let intensity = activeCalories / minutes
            return clampEffort(intensity / 1.4)
        case .other:
            return clampEffort(minutes / 12.0)
        }
    }

    /// Effort used for load: the user's RPE if they set one, else the estimate.
    public var effortScore: Int {
        if let rpe = userRPE { return min(max(rpe, 1), 10) }
        return autoEffort
    }

    /// Whether the effort reflects a user-entered RPE rather than the estimate.
    public var hasUserRPE: Bool { userRPE != nil }

    /// Cumulative load contribution (TRIMP-like): intensity × duration.
    public var loadValue: Double {
        Double(effortScore) * max(Double(durationMinutes), 1) / 10.0
    }

    private func clampEffort(_ raw: Double) -> Int {
        min(max(Int(raw.rounded()), 1), 10)
    }
}

public enum TrainingLoadStatus: String, Codable {
    case low, optimal, high, veryHigh

    public var label: String {
        switch self {
        case .low:      return "Basso"
        case .optimal:  return "Ottimale"
        case .high:     return "Alto"
        case .veryHigh: return "Molto alto"
        }
    }
}

public struct TrainingLoad: Codable {
    public let acute: Int        // last 7 days (sum of load)
    public let chronic: Int      // typical week (28-day average)
    public let ratio: Double     // acute / chronic
    public let status: TrainingLoadStatus
    public let weeklyEfforts: [Int]   // load per day, last 7 days (oldest→newest)
    /// Mean load per workout (90d, all categories) — baked into the synced struct
    /// so every device compares "vs your average" against the SAME number (the
    /// iPhone's), rather than each recomputing it from its own, possibly-diverged,
    /// local workout history. Used as the fallback when there isn't enough
    /// same-category history for `matchedAverageLoad(for:)` below.
    public let averageLoad: Double
    private let averageStrengthLoad: Double
    private let averageCardioLoad: Double
    private let averageOtherLoad: Double

    /// The average load to compare a SPECIFIC workout against: matches its
    /// category (cardio vs. strength vs. other) when there's enough same-category
    /// history, since a cardio session's "normal" load looks nothing like a
    /// strength session's — lumping them into one average made the comparison
    /// meaningless. Falls back to the all-category average otherwise.
    /// `matchedCategory` is nil when the fallback was used, so callers can label
    /// the comparison accordingly (e.g. "vs your average Cardio session").
    public func matchedAverageLoad(for session: WorkoutSession) -> (value: Double, matchedCategory: WorkoutCategory?) {
        let categoryAvg: Double
        switch session.category {
        case .strength: categoryAvg = averageStrengthLoad
        case .cardio:   categoryAvg = averageCardioLoad
        case .other:    categoryAvg = averageOtherLoad
        }
        if categoryAvg > 0 { return (categoryAvg, session.category) }
        return (averageLoad, nil)
    }

    private static let lambdaAcute   = 2.0 / (7.0 + 1.0)
    private static let lambdaChronic = 2.0 / (28.0 + 1.0)

    /// Daily session-RPE load (effort × duration), oldest → today, `days` long.
    private static func dailyLoads(from sessions: [WorkoutSession], days: Int, now: Date) -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var daily = [Double](repeating: 0, count: days)
        for s in sessions {
            let day = cal.startOfDay(for: s.startTime)
            if let offset = cal.dateComponents([.day], from: day, to: today).day,
               offset >= 0, offset < days {
                daily[days - 1 - offset] += s.loadValue
            }
        }
        return daily
    }

    private static func status(for ratio: Double) -> TrainingLoadStatus {
        switch ratio {
        case ..<0.8:  return .low
        case ..<1.3:  return .optimal
        case ..<1.5:  return .high
        default:      return .veryHigh
        }
    }

    /// Average load for one category over the last 90 days — 0 (meaning "use the
    /// fallback") if there are fewer than 2 sessions of that category, since a
    /// single past session isn't a meaningful "average" to compare against.
    private static func averageLoad(for category: WorkoutCategory, in sessions: [WorkoutSession],
                                    days: Int = 90, now: Date, minSamples: Int = 2) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        let matching = sessions.filter { $0.startTime >= cutoff && $0.category == category }
        guard matching.count >= minSamples else { return 0 }
        return matching.reduce(0.0) { $0 + $1.loadValue } / Double(matching.count)
    }

    public static func compute(from sessions: [WorkoutSession], now: Date = .now) -> TrainingLoad {
        // Window long enough for the chronic EWMA to settle.
        let daily = dailyLoads(from: sessions, days: 42, now: now)

        // Exponentially-weighted moving averages of daily load: acute (fatigue,
        // ~7-day) vs chronic (fitness, ~28-day). EWMA tracks the acute:chronic
        // workload ratio (ACWR) more faithfully than flat rolling averages —
        // recent days are weighted more (Williams et al., 2017).
        var acuteEWMA = 0.0, chronicEWMA = 0.0
        for v in daily {
            acuteEWMA   = lambdaAcute   * v + (1 - lambdaAcute)   * acuteEWMA
            chronicEWMA = lambdaChronic * v + (1 - lambdaChronic) * chronicEWMA
        }

        // Need ~a few weeks of history before the ratio is meaningful.
        let ratio = chronicEWMA >= 1.0 ? acuteEWMA / chronicEWMA : 1.0

        // Weekly-equivalent numbers so acute vs chronic are directly comparable.
        let weeklyEfforts = daily.suffix(7).map { Int($0.rounded()) }
        return TrainingLoad(acute: Int((acuteEWMA * 7).rounded()),
                            chronic: Int((chronicEWMA * 7).rounded()),
                            ratio: ratio,
                            status: status(for: ratio),
                            weeklyEfforts: Array(weeklyEfforts),
                            averageLoad: averageSessionLoad(from: sessions, now: now),
                            averageStrengthLoad: averageLoad(for: .strength, in: sessions, now: now),
                            averageCardioLoad: averageLoad(for: .cardio, in: sessions, now: now),
                            averageOtherLoad: averageLoad(for: .other, in: sessions, now: now))
    }

    /// Day-by-day acute/chronic trend (weekly-equivalent), so the ACWR balance
    /// can be charted over time instead of read as a single snapshot number.
    public static func history(from sessions: [WorkoutSession], days: Int = 56, now: Date = .now) -> [TrainingLoadPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let warmup = 42   // lead-in so the EWMA has settled by the first reported day
        let total = days + warmup
        let daily = dailyLoads(from: sessions, days: total, now: now)

        var acuteEWMA = 0.0, chronicEWMA = 0.0
        var points: [TrainingLoadPoint] = []
        for (i, v) in daily.enumerated() {
            acuteEWMA   = lambdaAcute   * v + (1 - lambdaAcute)   * acuteEWMA
            chronicEWMA = lambdaChronic * v + (1 - lambdaChronic) * chronicEWMA
            guard i >= warmup else { continue }
            let offsetFromToday = total - 1 - i
            guard let date = cal.date(byAdding: .day, value: -offsetFromToday, to: today) else { continue }
            let ratio = chronicEWMA >= 1.0 ? acuteEWMA / chronicEWMA : 1.0
            points.append(TrainingLoadPoint(date: date, acute: acuteEWMA * 7, chronic: chronicEWMA * 7,
                                            ratio: ratio, status: status(for: ratio)))
        }
        return points
    }

    /// How load over the last `days` splits across strength/cardio/other, so
    /// the source of the training stress is visible, not just its size.
    public static func loadByCategory(from sessions: [WorkoutSession], days: Int = 28, now: Date = .now) -> [CategoryLoad] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        var totals: [WorkoutCategory: Double] = [:]
        for s in sessions where s.startTime >= cutoff {
            totals[s.category, default: 0] += s.loadValue
        }
        return totals.map { CategoryLoad(category: $0.key, load: $0.value) }
            .sorted { $0.load > $1.load }
    }

    /// Average load per workout over a lookback window — a baseline for "was
    /// this session harder than usual?", distinct from its share of the week.
    public static func averageSessionLoad(from sessions: [WorkoutSession], days: Int = 90, now: Date = .now) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        let recent = sessions.filter { $0.startTime >= cutoff }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0.0) { $0 + $1.loadValue } / Double(recent.count)
    }
}

public struct TrainingLoadPoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let acute: Double
    public let chronic: Double
    public let ratio: Double
    public let status: TrainingLoadStatus
}

public struct CategoryLoad: Identifiable {
    public let id = UUID()
    public let category: WorkoutCategory
    public let load: Double
}

// MARK: - Recovery (sleep + heart)
//
// Sleep-weighted readiness 0–100: sleep quality 65%, HRV vs baseline 20%,
// resting HR vs baseline 15%. Heart components fall back gracefully when the
// baseline or today's reading is missing.

public enum RecoveryStatus: String {
    case poor, fair, good, excellent

    public var label: String {
        switch self {
        case .poor:      return "Scarso"
        case .fair:      return "Discreto"
        case .good:      return "Buono"
        case .excellent: return "Ottimo"
        }
    }
}

public struct RecoveryScore {
    public let overall: Int       // 0–100
    public let sleep: Int         // 0–100 component
    public let hrv: Int           // 0–100 component (100 = no data → neutral)
    public let restingHR: Int     // 0–100 component
    public let hasHeartData: Bool
    public let status: RecoveryStatus

    public init(sleepScore: Int,
                hrvToday: Double?, hrvBaseline: Double?,
                rhrToday: Double?, rhrBaseline: Double?) {
        let sleepC = Double(max(0, min(sleepScore, 100)))

        // HRV: higher than baseline = better recovery.
        var hrvC = 70.0
        if let v = hrvToday, let base = hrvBaseline, base > 0 {
            hrvC = min(max((v / base) * 70.0, 0), 100)
        }
        // Resting HR: lower than baseline = better recovery.
        var rhrC = 70.0
        if let v = rhrToday, v > 0, let base = rhrBaseline, base > 0 {
            rhrC = min(max((base / v) * 70.0, 0), 100)
        }

        let hasHeart = (hrvToday != nil && hrvBaseline != nil) ||
                       (rhrToday != nil && rhrBaseline != nil)

        let overallD: Double
        if hasHeart {
            overallD = sleepC * 0.65 + hrvC * 0.20 + rhrC * 0.15
        } else {
            overallD = sleepC   // sleep-only fallback
        }

        self.sleep = Int(sleepC.rounded())
        self.hrv = Int(hrvC.rounded())
        self.restingHR = Int(rhrC.rounded())
        self.hasHeartData = hasHeart
        self.overall = Int(overallD.rounded())

        switch self.overall {
        case ..<40:  self.status = .poor
        case ..<60:  self.status = .fair
        case ..<80:  self.status = .good
        default:     self.status = .excellent
        }
    }
}

// MARK: - Daily recommendation
//
// Combines today's readiness (RecoveryScore) with the acute:chronic training
// load into one actionable headline: push / keep the rhythm / go easy / rest.
// Either input can be missing (no sleep data, no workout history) — the
// recommendation degrades to whatever is available, or nil if neither is.

public struct DailyRecommendation: Codable {
    public enum Kind: String, Codable {
        case push, maintain, easy, rest, done

        public var title: String {
            switch self {
            case .push:     return "Giornata per spingere"
            case .maintain: return "Mantieni il ritmo"
            case .easy:     return "Giornata leggera"
            case .rest:     return "Meglio riposare"
            case .done:     return "Allenamento fatto"
            }
        }

        public var icon: String {
            switch self {
            case .push:     return "flame.fill"
            case .maintain: return "metronome.fill"
            case .easy:     return "figure.walk"
            case .rest:     return "moon.zzz.fill"
            case .done:     return "checkmark.seal.fill"
            }
        }
    }

    public let kind: Kind

    /// One localizable sentence of the reason: `key` is the Italian source
    /// sentence (the lookup key in each app's Localizable.strings), `args`
    /// fill its %@ placeholders. Kept structured so the composed reason can
    /// be localized at render time instead of baking Italian into the model —
    /// and Codable, so the iPhone-computed recommendation syncs to the watch
    /// and localizes against the WATCH's own tables.
    public struct ReasonFragment: Codable {
        public let key: String
        public let args: [String]
        init(_ key: String, _ args: [String] = []) {
            self.key = key
            self.args = args
        }
    }

    public let reasonFragments: [ReasonFragment]

    /// When this recommendation was computed — a recommendation is only valid
    /// for its own day, so consumers of a synced copy must check this.
    public let computedOn: Date

    /// The reason, localized against the running app's string tables
    /// (falls back to Italian where a key is missing).
    public var reason: String {
        reasonFragments.map { fragment in
            String(format: NSLocalizedString(fragment.key, comment: ""),
                   arguments: fragment.args)
        }.joined(separator: " ")
    }

    init(kind: Kind, reasonFragments: [ReasonFragment], computedOn: Date = .now) {
        self.kind = kind
        self.reasonFragments = reasonFragments
        self.computedOn = computedOn
    }

    /// `recovery` should be passed as nil when there's no real data behind it
    /// (e.g. overall == 0 because the watch wasn't worn at night) — a missing
    /// input is degraded gracefully, a fake zero would force "rest" forever.
    /// The extra context (today's workout, session history, weekly goal) adds
    /// the states a pure recovery/load model can't see: "already trained
    /// today", "N days idle, come back", "one short of the weekly goal".
    public static func compute(recovery: RecoveryScore?, load: TrainingLoad?,
                               hasWorkedOutToday: Bool = false,
                               sessions: [WorkoutSession] = [],
                               weeklyWorkoutGoal: Int? = nil,
                               now: Date = .now) -> DailyRecommendation? {
        // A load with no chronic baseline yet says nothing about overreaching.
        let usableLoad = (load?.chronic ?? 0) > 0 ? load : nil
        guard recovery != nil || usableLoad != nil || hasWorkedOutToday else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let workoutsThisWeek = sessions.filter { $0.startTime >= weekStart && $0.startTime <= now }.count
        let daysSinceLast: Int? = sessions.map(\.startTime).max().flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0),
                                    to: calendar.startOfDay(for: now)).day
        }

        // Already trained today → the job is recovery, not more prescriptions.
        if hasWorkedOutToday {
            var fragments = [ReasonFragment("Oggi hai già dato.")]
            if let goal = weeklyWorkoutGoal, goal > 0 {
                fragments.append(workoutsThisWeek >= goal
                    ? ReasonFragment("Obiettivo settimanale completato: %@ su %@ 🎯.",
                                     ["\(workoutsThisWeek)", "\(goal)"])
                    : ReasonFragment("Sei a %@ su %@ questa settimana.",
                                     ["\(workoutsThisWeek)", "\(goal)"]))
            }
            fragments.append(ReasonFragment("Ora contano recupero, proteine e sonno."))
            return DailyRecommendation(kind: .done, reasonFragments: fragments)
        }

        if let l = usableLoad, l.status == .veryHigh {
            return DailyRecommendation(kind: .rest, reasonFragments: [
                ReasonFragment("Carico molto sopra la tua norma: una pausa oggi riduce il rischio di sovrallenamento.")])
        }
        if let r = recovery, r.status == .poor {
            return DailyRecommendation(kind: .rest, reasonFragments: [
                ReasonFragment("Recupero basso (%@/100): il corpo sta ancora recuperando.", ["\(r.overall)"])])
        }
        if let l = usableLoad, l.status == .high {
            return DailyRecommendation(kind: .easy, reasonFragments: [
                ReasonFragment("Stai caricando più del solito: meglio tenere bassa l'intensità.")])
        }
        if let r = recovery, r.status == .fair {
            return DailyRecommendation(kind: .easy, reasonFragments: [
                ReasonFragment("Recupero parziale (%@/100): un'attività leggera è la scelta giusta.", ["\(r.overall)"])])
        }

        // Fatigue gate: recovery scores lag accumulated work, so "push" must
        // consider what was actually done recently, not recovery alone.
        // NO consecutive-day requirement — a rest day between two heavy
        // sessions doesn't erase their fatigue (that requirement is exactly
        // why a Mon/Wed lifter kept seeing "push" on Thursday). Windows are
        // calendar days, so an evening session doesn't age out mid-day.
        let today = calendar.startOfDay(for: now)

        // Tunables — per the user: the light-day hint fires only when there
        // was a genuinely HEAVY workout in the previous 2 days; one is enough.
        let hardWindowDays = 2           // "recent" = today + yesterday
        let hardSessionFactor = 0.9      // ≥ 90% of the usual session load
        let hardEffortThreshold = 7.5    // session RPE
        let compressedWeekShare = 0.45   // 3-day load ≥ 45% of the weekly norm

        if let windowStart = calendar.date(byAdding: .day, value: -(hardWindowDays - 1), to: today) {
            let recent = sessions.filter { $0.startTime >= windowStart }
            if let l = usableLoad, l.averageLoad > 0 {
                let hardByLoad = recent.filter { $0.loadValue >= l.averageLoad * hardSessionFactor }
                if !hardByLoad.isEmpty {
                    return DailyRecommendation(kind: .easy, reasonFragments: [
                        ReasonFragment("Hai fatto %@ sessioni intense negli ultimi %@ giorni: meglio una giornata leggera.",
                                       ["\(hardByLoad.count)", "\(hardWindowDays)"])])
                }
            }
            // High RPE marks a session as hard even when its load stays
            // under the baseline (short heavy sessions barely move load).
            let hardByEffort = recent.filter { Double($0.effortScore) >= hardEffortThreshold }
            if !hardByEffort.isEmpty {
                let avgEffort = hardByEffort.reduce(0.0) { $0 + Double($1.effortScore) }
                    / Double(hardByEffort.count)
                return DailyRecommendation(kind: .easy, reasonFragments: [
                    ReasonFragment("Hai fatto %@ sessioni con sforzo alto negli ultimi %@ giorni (RPE medio %@): meglio una giornata leggera.",
                                   ["\(hardByEffort.count)", "\(hardWindowDays)", String(format: "%.1f", avgEffort)])])
            }
        }
        if let l = usableLoad, l.chronic > 0,
           let shareWindowStart = calendar.date(byAdding: .day, value: -2, to: today) {
            let recentLoad = sessions
                .filter { $0.startTime >= shareWindowStart }
                .reduce(0.0) { $0 + $1.loadValue }
            let share = recentLoad / Double(l.chronic)
            if share >= compressedWeekShare {
                return DailyRecommendation(kind: .easy, reasonFragments: [
                    ReasonFragment("Negli ultimi 3 giorni hai accumulato il %@%% del tuo carico settimanale medio: meglio una giornata leggera.",
                                   ["\(Int((share * 100).rounded()))"])])
            }
        }

        // From here on recovery is good (or unknown), load is optimal/low and
        // recent work isn't stacked up — the only state where "push" fits.
        if let days = daysSinceLast, days >= 3 {
            return DailyRecommendation(kind: .push, reasonFragments: [
                ReasonFragment("Sono %@ giorni dall'ultimo allenamento e sei recuperato: oggi è il giorno giusto per riprendere.", ["\(days)"])])
        }
        if let goal = weeklyWorkoutGoal, goal > 0, workoutsThisWeek == goal - 1 {
            return DailyRecommendation(kind: .push, reasonFragments: [
                ReasonFragment("Te ne manca uno solo per l'obiettivo settimanale (%@ su %@): giornata giusta per chiuderlo.",
                               ["\(workoutsThisWeek)", "\(goal)"])])
        }
        if let l = usableLoad, l.status == .low, recovery == nil || recovery!.overall >= 60 {
            return DailyRecommendation(kind: .push, reasonFragments: [
                ReasonFragment("Sei recuperato e il carico è sotto la tua media: giornata ideale per un allenamento intenso.")])
        }

        var fragments = [ReasonFragment("Recupero e carico in equilibrio: continua con il tuo ritmo abituale.")]
        if let goal = weeklyWorkoutGoal, goal > 0 {
            fragments.append(ReasonFragment("Questa settimana: %@ su %@ allenamenti.",
                                            ["\(workoutsThisWeek)", "\(goal)"]))
        }
        return DailyRecommendation(kind: .maintain, reasonFragments: fragments)
    }
}
