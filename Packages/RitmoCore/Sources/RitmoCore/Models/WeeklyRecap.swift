import Foundation

// MARK: - WeeklyRecap
//
// Summary of the last COMPLETED week (Monday–Sunday), with deltas against the
// week before it. Workout numbers come from the local session store; sleep is
// averaged over the sessions passed in (whoever calls decides how far back to
// fetch — the recapped week needs at most 13 days of history).

public struct WeeklyRecap {
    public let weekStart: Date            // first day of the recapped week
    public let weekEnd: Date              // exclusive (start of current week)
    public let workoutCount: Int
    public let previousWorkoutCount: Int
    public let totalLoad: Double
    public let previousLoad: Double
    public let activeDays: Int            // distinct days with ≥1 workout
    public let avgSleepHours: Double      // 0 = no sleep data that week
    public let bestSessionTitle: String?  // highest-load workout of the week
    public let bestSessionLoad: Double

    /// Load change vs the previous week, as a percentage; nil when there's no
    /// previous-week baseline to compare against.
    public var loadDeltaPercent: Double? {
        guard previousLoad > 0 else { return nil }
        return (totalLoad - previousLoad) / previousLoad * 100
    }

    /// Last day INSIDE the recapped week (for display ranges).
    public var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
    }

    public static func compute(sessions: [WorkoutSession],
                               sleepSessions: [SleepSession],
                               now: Date = .now,
                               calendar: Calendar = .current) -> WeeklyRecap? {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let recapStart = calendar.date(byAdding: .day, value: -7, to: currentWeek.start),
              let previousStart = calendar.date(byAdding: .day, value: -14, to: currentWeek.start)
        else { return nil }
        let recapEnd = currentWeek.start

        let recapped = sessions.filter { $0.startTime >= recapStart && $0.startTime < recapEnd }
        let previous = sessions.filter { $0.startTime >= previousStart && $0.startTime < recapStart }

        // A sleep session belongs to the recapped week if you woke up in it.
        let recapSleep = sleepSessions.filter { $0.endTime >= recapStart && $0.endTime < recapEnd }
        let avgSleep = recapSleep.isEmpty ? 0
            : recapSleep.reduce(0.0) { $0 + $1.totalHours } / Double(recapSleep.count)

        // Nothing worth recapping: no training either week and no sleep data.
        guard !recapped.isEmpty || !previous.isEmpty || !recapSleep.isEmpty else { return nil }

        let best = recapped.max { $0.loadValue < $1.loadValue }
        let activeDays = Set(recapped.map { calendar.startOfDay(for: $0.startTime) }).count

        return WeeklyRecap(
            weekStart: recapStart,
            weekEnd: recapEnd,
            workoutCount: recapped.count,
            previousWorkoutCount: previous.count,
            totalLoad: recapped.reduce(0.0) { $0 + $1.loadValue },
            previousLoad: previous.reduce(0.0) { $0 + $1.loadValue },
            activeDays: activeDays,
            avgSleepHours: avgSleep,
            bestSessionTitle: best?.title,
            bestSessionLoad: best?.loadValue ?? 0
        )
    }
}
