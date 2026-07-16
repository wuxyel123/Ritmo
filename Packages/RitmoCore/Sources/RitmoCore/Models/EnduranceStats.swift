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

    // MARK: Riegel equivalent times

    public struct EquivalentTime: Identifiable {
        public let id = UUID()
        public let bucket: DistanceBucket
        public let seconds: Int
        public let sourceLabel: String     // the PB it was predicted from (loc key)
    }

    /// Predicted times per canonical distance via the Riegel formula
    /// (t₂ = t₁ × (d₂/d₁)^1.06), each derived from the PB at the CLOSEST
    /// other distance — predictions degrade with distance ratio, so the
    /// nearest anchor is the most defensible one.
    public static func riegelEquivalents(from pbs: [PersonalBest],
                                         sport: Sport = .run) -> [EquivalentTime] {
        guard !pbs.isEmpty else { return [] }
        return buckets(for: sport).compactMap { target in
            let source = pbs
                .filter { $0.bucket.meters != target.meters }
                .min { a, b in
                    abs(log(a.bucket.meters / target.meters)) < abs(log(b.bucket.meters / target.meters))
                }
            guard let source else { return nil }
            let predicted = Double(source.durationSeconds)
                * pow(target.meters / source.bucket.meters, 1.06)
            return EquivalentTime(bucket: target,
                                  seconds: Int(predicted.rounded()),
                                  sourceLabel: source.bucket.label)
        }
    }

    // MARK: Pace ↔ heart-rate model

    /// Linear speed-vs-HR relationship fitted on the user's own runs.
    /// Valid inside the observed HR/pace range; callers must disclose
    /// extrapolation beyond it (same rule as the RTS and WMA tables).
    public struct PaceHRModel {
        public let slope: Double            // m/s gained per bpm
        public let intercept: Double        // m/s at 0 bpm (mathematical anchor only)
        public let runCount: Int
        public let hrRange: ClosedRange<Double>     // observed per-run average HR
        public let paceRange: ClosedRange<Double>   // observed sec/km (fastest…slowest)

        public func paceSecondsPerKm(atHR hr: Double) -> Double? {
            let speed = intercept + slope * hr
            guard speed > 0.3 else { return nil }   // slower than ~55 min/km: no signal
            return 1000 / speed
        }

        public func hr(atPaceSecondsPerKm pace: Double) -> Double? {
            guard pace > 0, slope > 0 else { return nil }
            return (1000 / pace - intercept) / slope
        }
    }

    /// Least-squares fit of speed (m/s) against average heart rate across
    /// steady runs. Nil below 5 usable runs, when the HR values barely
    /// spread (< 8 bpm — a vertical cloud has no slope), or when the slope
    /// comes out non-positive (faster at lower HR is noise, not physiology).
    public static func paceHRModel(points: [(hr: Double, speedMps: Double)]) -> PaceHRModel? {
        let pts = points.filter { $0.hr > 60 && $0.hr < 230 && $0.speedMps > 0.5 }
        guard pts.count >= 5 else { return nil }
        let hrs = pts.map(\.hr)
        guard let minHR = hrs.min(), let maxHR = hrs.max(), maxHR - minHR >= 8 else { return nil }

        let n = Double(pts.count)
        let meanHR = hrs.reduce(0, +) / n
        let meanSpeed = pts.reduce(0) { $0 + $1.speedMps } / n
        var sxx = 0.0, sxy = 0.0
        for p in pts {
            sxx += (p.hr - meanHR) * (p.hr - meanHR)
            sxy += (p.hr - meanHR) * (p.speedMps - meanSpeed)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        guard slope > 0 else { return nil }

        let paces = pts.map { 1000 / $0.speedMps }
        return PaceHRModel(slope: slope,
                           intercept: meanSpeed - slope * meanHR,
                           runCount: pts.count,
                           hrRange: minHR...maxHR,
                           paceRange: paces.min()!...paces.max()!)
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
