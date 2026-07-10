import Foundation

// MARK: - EnduranceStats
//
// Cardio counterpart of WorkoutStats: personal bests per canonical distance
// and weekly volume, computed from the sessions already in the store plus
// the race log. Same rules as everything else on the Statistiche screen:
// pure passes over the data, computed once by the view, data-only output.

public enum EnduranceStats {

    public enum Sport: CaseIterable {
        case run, ride

        /// HKWorkoutActivityType raw values that belong to this sport.
        var activityTypes: Set<Int> {
            switch self {
            case .run:  return [37]        // .running
            case .ride: return [13]        // .cycling
            }
        }

        public var raceSport: RaceSport {
            switch self {
            case .run:  return .run
            case .ride: return .ride
            }
        }
    }

    public struct DistanceBucket {
        public let label: String           // "5 km", "Maratona"… (localization key)
        public let meters: Double
        public let gradingDistance: AgeGrading.Distance?   // runs only
    }

    /// Canonical distances per sport. A session/race matches a bucket when
    /// its distance is within −3%…+8% of the target: GPS overshoot is normal,
    /// but a 12 km run does NOT count as a 10 km effort — without splits the
    /// 10 km time inside it can't be known.
    public static func buckets(for sport: Sport) -> [DistanceBucket] {
        switch sport {
        case .run:
            return [DistanceBucket(label: "5 km", meters: 5_000, gradingDistance: .fiveK),
                    DistanceBucket(label: "10 km", meters: 10_000, gradingDistance: .tenK),
                    DistanceBucket(label: "Mezza maratona", meters: 21_097.5, gradingDistance: .halfMarathon),
                    DistanceBucket(label: "Maratona", meters: 42_195, gradingDistance: .marathon)]
        case .ride:
            return [DistanceBucket(label: "25 km", meters: 25_000, gradingDistance: nil),
                    DistanceBucket(label: "50 km", meters: 50_000, gradingDistance: nil),
                    DistanceBucket(label: "100 km", meters: 100_000, gradingDistance: nil)]
        }
    }

    public struct PersonalBest: Identifiable {
        public let id = UUID()
        public let bucket: DistanceBucket
        public let date: Date
        public let durationSeconds: Int
        public let distanceMeters: Double
        public let isRace: Bool
        public let raceName: String?

        public var paceSecondsPerKm: Double {
            Double(durationSeconds) / (distanceMeters / 1000)
        }
        public var speedKmH: Double {
            (distanceMeters / 1000) / (Double(durationSeconds) / 3600)
        }
    }

    private static func matches(_ meters: Double, bucket: DistanceBucket) -> Bool {
        meters >= bucket.meters * 0.97 && meters <= bucket.meters * 1.08
    }

    /// Best time per canonical distance, from recorded sessions AND logged
    /// races (a race result can beat any training effort and vice versa).
    public static func personalBests(sport: Sport,
                                     sessions: [WorkoutSession],
                                     races: [RaceResult]) -> [PersonalBest] {
        buckets(for: sport).compactMap { bucket in
            var best: PersonalBest?

            for session in sessions where sport.activityTypes.contains(session.hkActivityType) {
                let seconds = Int(session.endTime.timeIntervalSince(session.startTime))
                guard seconds > 0, matches(session.distanceMeters, bucket: bucket) else { continue }
                if best == nil || seconds < best!.durationSeconds {
                    best = PersonalBest(bucket: bucket, date: session.startTime,
                                        durationSeconds: seconds,
                                        distanceMeters: session.distanceMeters,
                                        isRace: false, raceName: nil)
                }
            }
            for race in races where race.sport == sport.raceSport {
                guard race.durationSeconds > 0,
                      matches(race.distanceMeters, bucket: bucket) else { continue }
                if best == nil || race.durationSeconds < best!.durationSeconds {
                    best = PersonalBest(bucket: bucket, date: race.date,
                                        durationSeconds: race.durationSeconds,
                                        distanceMeters: race.distanceMeters,
                                        isRace: true, raceName: race.name)
                }
            }
            return best
        }
    }

    /// Distance per calendar week (km), oldest → current week — the cardio
    /// twin of WorkoutStats.weeklyTonnage.
    public static func weeklyDistanceKm(sport: Sport,
                                        from sessions: [WorkoutSession],
                                        weeks: Int = 12,
                                        now: Date = .now) -> [WorkoutStats.WeekPoint] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }

        var km = [Double](repeating: 0, count: weeks)
        for session in sessions
        where sport.activityTypes.contains(session.hkActivityType) && session.startTime >= firstWeek {
            if let weeksAgo = calendar.dateComponents(
                [.weekOfYear],
                from: calendar.dateInterval(of: .weekOfYear, for: session.startTime)?.start ?? session.startTime,
                to: thisWeek).weekOfYear,
               weeksAgo >= 0, weeksAgo < weeks {
                km[weeks - 1 - weeksAgo] += session.distanceMeters / 1000
            }
        }
        return (0..<weeks).compactMap { i in
            calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - i), to: thisWeek)
                .map { WorkoutStats.WeekPoint(weekStart: $0, value: km[i]) }
        }
    }

    /// h:mm:ss / mm:ss for race times.
    public static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// min/km pace string ("4'32\"").
    public static func formatPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "—" }
        let m = Int(secondsPerKm) / 60, s = Int(secondsPerKm) % 60
        return String(format: "%d'%02d\"", m, s)
    }
}
