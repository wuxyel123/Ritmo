import Foundation

// MARK: - MeetPlan
//
// Attempt selection and the warm-up ramp that leads into it. Kept together
// because they are one continuous ladder: the warm-ups only make sense
// relative to the opener they are building towards.

public enum MeetPlan {

    /// Everything rounded to the 2.5 kg that actually exists on the bar.
    public static func plateRounded(_ kg: Double) -> Double {
        (kg / 2.5).rounded() * 2.5
    }

    public static let barKg: Double = 20

    /// Step between attempts: 4% of the max, plate-rounded — 10 kg on a
    /// 245 kg lift, which is what a lifter actually takes.
    public static func attemptJump(oneRM: Double) -> Double {
        Swift.max(plateRounded(oneRM * 0.04), 2.5)
    }

    /// Opener / second / third, counted DOWN from the max: the third attempt
    /// IS the max, and the two below it sit one jump apart each. Anchoring on
    /// 100% keeps the ladder in whole steps a lifter can call out — 225, 235,
    /// 245 — instead of the 91/97/101% split, whose uneven 6%-then-4% gaps
    /// were what made the approach to the opener come out too short.
    public static func attempts(oneRM: Double) -> [Double] {
        let third = plateRounded(oneRM)
        let jump = attemptJump(oneRM: oneRM)
        return [third - 2 * jump, third - jump, third]
    }

    public struct WarmupSet {
        public let kg: Double
        public let reps: Int
        /// Share of the max this set actually lands on, after rounding.
        public let percentOfMax: Int
    }

    /// The warm-up ramp, built DOWNWARDS from the opener rather than from
    /// fixed percentages of the max. A percentage ladder looks tidy but the
    /// jumps it produces depend on where 2.5 kg rounding happens to land, so
    /// it kept asking for a shorter step into the opener than the steps
    /// between the attempts themselves — backwards, and exactly the bug this
    /// replaces. Walking down instead makes the rule structural: the approach
    /// to the opener is one full attempt-sized step, the step below it the
    /// same, and every earlier one only coarser.
    ///
    /// For a 245 kg max that gives 72.5, 132.5, 162.5, 192.5, 207.5 into
    /// 222.5 — jumps of 60/30/30/15/15/15, mirroring how a lifter actually
    /// opens a meet.
    public static func warmups(oneRM: Double) -> [WarmupSet] {
        guard oneRM > 0 else { return [] }
        let attempts = attempts(oneRM: oneRM)
        let opener = attempts[0]
        // Never shorter than the gap between attempts, and never a token
        // 2.5 kg step on a heavy bar.
        let step = Swift.max(attempts[1] - opener, plateRounded(oneRM * 0.06), 2.5)
        // Two fine steps under the opener, then progressively coarser ones.
        // Five rungs: enough to land the first one near 30% of the max, and
        // going deeper only adds sets barely above the empty bar.
        let spacing: [Double] = [1, 1, 2, 2, 4]
        let repsFromTop = [1, 1, 2, 3, 5]

        var descending: [WarmupSet] = []
        var current = opener
        for (index, multiplier) in spacing.enumerated() {
            current -= step * multiplier
            let kg = plateRounded(current)
            // Stop once the rung sits on top of the empty bar: a 25 kg set
            // after a 20 kg bar is a rung nobody would load.
            guard kg >= barKg + 10 else { break }
            descending.append(WarmupSet(kg: kg, reps: repsFromTop[index],
                                        percentOfMax: Int((kg / oneRM * 100).rounded())))
        }
        return descending.reversed()
    }

    /// Every loaded weight in order — warm-ups then attempts. The empty bar is
    /// left out on purpose: it is a fixed 20 kg starting point, not a rung
    /// chosen by the ramp, so the "jumps never grow" rule starts above it.
    public static func ladder(oneRM: Double) -> [Double] {
        warmups(oneRM: oneRM).map(\.kg) + attempts(oneRM: oneRM)
    }
}
