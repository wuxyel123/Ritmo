import Foundation

// MARK: - Workout effort & training load
//
// Apple-style training load: recent (7-day) load vs a 28-day baseline.
// Per-workout effort is a 1–10 RPE-like score. Strength work (powerlifting etc.)
// sits in HR zone 1 yet is high-intensity, so calories under-rate it — we score
// strength by duration, and cardio by calorie intensity.

public enum WorkoutCategory {
    case strength, cardio, other
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

public enum TrainingLoadStatus: String {
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

public struct TrainingLoad {
    public let acute: Int        // last 7 days (sum of load)
    public let chronic: Int      // typical week (28-day average)
    public let ratio: Double     // acute / chronic
    public let status: TrainingLoadStatus
    public let weeklyEfforts: [Int]   // load per day, last 7 days (oldest→newest)

    public static func compute(from sessions: [WorkoutSession], now: Date = .now) -> TrainingLoad {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        func load(inLastDays days: Int) -> Double {
            let cutoff = cal.date(byAdding: .day, value: -days, to: today) ?? .distantPast
            return sessions.filter { $0.startTime >= cutoff }.reduce(0) { $0 + $1.loadValue }
        }

        let acute = load(inLastDays: 7)
        let chronicWeek = load(inLastDays: 28) / 4.0   // average week over 28 days
        let ratio = chronicWeek > 0 ? acute / chronicWeek : (acute > 0 ? 2.0 : 0)

        let status: TrainingLoadStatus
        switch ratio {
        case ..<0.8:  status = .low
        case ..<1.3:  status = .optimal
        case ..<1.6:  status = .high
        default:      status = .veryHigh
        }

        // Per-day load for the last 7 days (oldest → newest) for a mini bar chart.
        var daily: [Int] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { daily.append(0); continue }
            let v = sessions
                .filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
                .reduce(0.0) { $0 + $1.loadValue }
            daily.append(Int(v.rounded()))
        }

        return TrainingLoad(acute: Int(acute.rounded()),
                            chronic: Int(chronicWeek.rounded()),
                            ratio: ratio,
                            status: status,
                            weeklyEfforts: daily)
    }
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
