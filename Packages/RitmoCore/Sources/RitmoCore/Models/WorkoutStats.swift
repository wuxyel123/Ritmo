import Foundation

// MARK: - WorkoutStats
//
// Aggregations for the Statistiche screen — every function is a pure pass
// over the stored sessions, computed once by the view and cached in @State
// (never call these from a computed property: full-store passes per body
// evaluation are exactly the lag class fixed in TrainingLoadDetailView).
// All outputs are DATA (counts, kg, days) — the UI states them without
// judgment, per the data-only rule.

public enum WorkoutStats {

    // MARK: Weekly buckets

    public struct WeekPoint: Identifiable {
        public let id = UUID()
        public let weekStart: Date
        public let value: Double
    }

    /// Start of the calendar week `offset` weeks before the current one.
    private static func weekStart(offsetFromNow offset: Int, calendar: Calendar, now: Date) -> Date? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        return calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)
    }

    /// Sets per calendar week, oldest → current week. `group` nil = all groups.
    /// Warm-up sets are excluded: the sets-per-muscle-per-week number people
    /// track counts working sets.
    public static func weeklySets(from sessions: [WorkoutSession],
                                  group: MuscleGroup? = nil,
                                  weeks: Int = 8,
                                  now: Date = .now) -> [WeekPoint] {
        let calendar = Calendar.current
        guard let firstWeek = weekStart(offsetFromNow: weeks - 1, calendar: calendar, now: now) else { return [] }

        var counts = [Int](repeating: 0, count: weeks)
        for session in sessions where session.startTime >= firstWeek {
            for set in session.sets where set.setType != .warmup {
                if let group {
                    guard let exercise = set.exercise,
                          exercise.muscleGroup == group
                            || exercise.secondaryMuscleGroups.contains(group) else { continue }
                }
                if let weeksAgo = calendar.dateComponents(
                    [.weekOfYear], from: calendar.dateInterval(of: .weekOfYear, for: session.startTime)?.start ?? session.startTime,
                    to: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now).weekOfYear,
                   weeksAgo >= 0, weeksAgo < weeks {
                    counts[weeks - 1 - weeksAgo] += 1
                }
            }
        }
        return (0..<weeks).compactMap { i in
            weekStart(offsetFromNow: weeks - 1 - i, calendar: calendar, now: now)
                .map { WeekPoint(weekStart: $0, value: Double(counts[i])) }
        }
    }

    /// Total tonnage (kg × reps, warm-ups included — it's all mechanical work)
    /// per calendar week, oldest → current week.
    public static func weeklyTonnage(from sessions: [WorkoutSession],
                                     weeks: Int = 12,
                                     now: Date = .now) -> [WeekPoint] {
        let calendar = Calendar.current
        guard let firstWeek = weekStart(offsetFromNow: weeks - 1, calendar: calendar, now: now) else { return [] }

        var tonnage = [Double](repeating: 0, count: weeks)
        for session in sessions where session.startTime >= firstWeek {
            let volume = session.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps ?? 0) }
            guard volume > 0 else { continue }
            if let weeksAgo = calendar.dateComponents(
                [.weekOfYear], from: calendar.dateInterval(of: .weekOfYear, for: session.startTime)?.start ?? session.startTime,
                to: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now).weekOfYear,
               weeksAgo >= 0, weeksAgo < weeks {
                tonnage[weeks - 1 - weeksAgo] += volume
            }
        }
        return (0..<weeks).compactMap { i in
            weekStart(offsetFromNow: weeks - 1 - i, calendar: calendar, now: now)
                .map { WeekPoint(weekStart: $0, value: tonnage[i]) }
        }
    }

    // MARK: Rep ranges

    public struct RepRangeSplit {
        public let strength: Int      // 1–5 reps
        public let hypertrophy: Int   // 6–12
        public let endurance: Int     // 13+
        public var total: Int { strength + hypertrophy + endurance }

        public init(strength: Int, hypertrophy: Int, endurance: Int) {
            self.strength = strength
            self.hypertrophy = hypertrophy
            self.endurance = endurance
        }
    }

    /// Working-set counts by rep range over the last `days`.
    public static func repRangeSplit(from sessions: [WorkoutSession],
                                     days: Int = 28,
                                     now: Date = .now) -> RepRangeSplit {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        var strength = 0, hypertrophy = 0, endurance = 0
        for session in sessions where session.startTime >= cutoff {
            for set in session.sets where set.setType != .warmup {
                guard let reps = set.reps, reps > 0 else { continue }
                switch reps {
                case 1...5:   strength += 1
                case 6...12:  hypertrophy += 1
                default:      endurance += 1
                }
            }
        }
        return RepRangeSplit(strength: strength, hypertrophy: hypertrophy, endurance: endurance)
    }

    // MARK: Muscle-group frequency

    public struct GroupFrequency: Identifiable {
        public var id: MuscleGroup { group }
        public let group: MuscleGroup
        public let workoutDays: Int          // distinct days trained in window
        public let perWeek: Double           // workoutDays scaled to a week
        public let averageGapDays: Double?   // mean days between hits (nil < 2 hits)
    }

    /// How often each muscle group gets trained over the last `days`
    /// (primary OR secondary involvement), most-frequent first.
    public static func muscleGroupFrequency(from sessions: [WorkoutSession],
                                            days: Int = 28,
                                            now: Date = .now) -> [GroupFrequency] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        var daysByGroup: [MuscleGroup: Set<Date>] = [:]
        for session in sessions where session.startTime >= cutoff {
            let day = calendar.startOfDay(for: session.startTime)
            var groups: Set<MuscleGroup> = []
            for set in session.sets {
                guard let exercise = set.exercise else { continue }
                groups.insert(exercise.muscleGroup)
                groups.formUnion(exercise.secondaryMuscleGroups)
            }
            for group in groups { daysByGroup[group, default: []].insert(day) }
        }
        return daysByGroup.map { group, trainedDays in
            let sorted = trainedDays.sorted()
            var gap: Double? = nil
            if sorted.count >= 2 {
                let total = zip(sorted.dropFirst(), sorted).reduce(0.0) {
                    $0 + $1.0.timeIntervalSince($1.1) / 86_400
                }
                gap = total / Double(sorted.count - 1)
            }
            return GroupFrequency(group: group,
                                  workoutDays: sorted.count,
                                  perWeek: Double(sorted.count) / (Double(days) / 7.0),
                                  averageGapDays: gap)
        }
        .sorted { $0.workoutDays > $1.workoutDays }
    }

    // MARK: Session density

    /// kg moved per minute, per session with volume, over the last `days`
    /// (oldest → newest) — shows whether the same gym hour carries more work.
    public static func sessionDensity(from sessions: [WorkoutSession],
                                      days: Int = 90,
                                      now: Date = .now) -> [DateValuePoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        return sessions
            .filter { $0.startTime >= cutoff }
            .compactMap { session in
                let volume = session.sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps ?? 0) }
                let minutes = Double(session.durationMinutes)
                guard volume > 0, minutes >= 10 else { return nil }
                return DateValuePoint(date: session.startTime, value: volume / minutes)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: Top exercises

    public struct ExerciseSummary: Identifiable {
        public let id = UUID()
        public let name: String
        public let totalVolume: Double
        public let setCount: Int
        public let bestE1RM: Double        // 0 when no weighted set qualifies
        public let lastPerformed: Date
    }

    /// Exercises ranked by total volume, with their headline numbers —
    /// the entry list for per-exercise progression.
    public static func exerciseSummaries(from sessions: [WorkoutSession]) -> [ExerciseSummary] {
        struct Accumulator {
            var volume = 0.0, sets = 0, bestE1RM = 0.0
            var last = Date.distantPast
        }
        var byName: [String: Accumulator] = [:]
        for session in sessions {
            for set in session.sets {
                guard let name = set.exercise?.name else { continue }
                var acc = byName[name] ?? Accumulator()
                let reps = set.reps ?? 0
                acc.volume += set.weightKg * Double(reps)
                acc.sets += 1
                if set.setType != .warmup, set.weightKg > 0, (1...12).contains(reps) {
                    acc.bestE1RM = max(acc.bestE1RM, set.weightKg * (1 + Double(reps) / 30.0))
                }
                acc.last = max(acc.last, session.startTime)
                byName[name] = acc
            }
        }
        return byName.map { name, acc in
            ExerciseSummary(name: name, totalVolume: acc.volume, setCount: acc.sets,
                            bestE1RM: acc.bestE1RM, lastPerformed: acc.last)
        }
        .sorted { $0.totalVolume > $1.totalVolume }
    }

    // MARK: IPF GL points (SBD)

    /// The three competition lifts — matched by exact catalog name (the
    /// user's Hevy vocabulary), variants (front/box/pause squat, close-grip
    /// bench, Romanian deadlift…) deliberately don't count toward a total.
    public enum SBDLift: CaseIterable {
        case squat, bench, deadlift

        public static func classify(_ exerciseName: String?) -> SBDLift? {
            switch exerciseName?.lowercased() {
            case "squat (bilanciere)", "squat (barbell)":                 return .squat
            case "panca piana (bilanciere)", "bench press (barbell)":     return .bench
            case "stacco da terra (bilanciere)", "deadlift (barbell)":    return .deadlift
            default:                                                      return nil
            }
        }
    }

    /// IPF GL points (the 2020 "GoodLift" formula, classic raw SBD):
    /// total × 100 / (A − B·e^(−C·BW)). Comparable across body weights.
    public static func ipfGLPoints(total: Double, bodyWeightKg: Double, isFemale: Bool) -> Double {
        let (a, b, c) = isFemale
            ? (610.32796, 1045.59282, 0.03048)
            : (1199.72839, 1025.18162, 0.00921)
        let denominator = a - b * exp(-c * bodyWeightKg)
        guard denominator > 0, total > 0 else { return 0 }
        return total * 100 / denominator
    }

    // MARK: Per-exercise volume history

    /// Volume per session for one exercise (oldest → newest) — the third
    /// progression chart next to PRService.progression's weight/e1RM.
    public static func volumeHistory(for exerciseName: String,
                                     in sessions: [WorkoutSession]) -> [DateValuePoint] {
        sessions
            .compactMap { session in
                let volume = session.sets
                    .filter { $0.exercise?.name == exerciseName }
                    .reduce(0.0) { $0 + $1.weightKg * Double($1.reps ?? 0) }
                return volume > 0 ? DateValuePoint(date: session.startTime, value: volume) : nil
            }
            .sorted { $0.date < $1.date }
    }
}
