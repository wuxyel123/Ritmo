import SwiftUI

/// Shared scale for nutrition adherence — drives BOTH the bar/ring color
/// (identical across every view and both apps) and the nutrition score penalty.
public enum NutritionScale {

    /// 0...1 adherence: full credit within ±5% of the goal, falling linearly to
    /// 0 once you're ±50% off (under OR over). Used by the day score so that, e.g.,
    /// a 2000 kcal goal with 3000 eaten yields no calorie credit.
    public static func adherence(value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        let deviation = abs(value / goal - 1.0)
        if deviation <= 0.05 { return 1.0 }
        if deviation >= 0.50 { return 0.0 }
        return 1.0 - (deviation - 0.05) / 0.45
    }

    /// Shared progress color: red when far under, green near the goal, red again
    /// when overshooting by a lot — same color at the same percentage everywhere.
    public static func color(value: Double, goal: Double) -> Color {
        guard goal > 0 else { return .gray }
        let ratio = value / goal
        let position: Double = ratio <= 1.0
            ? ratio                                  // 0 (red) → 1 (green) while filling
            : max(0, 1.0 - (ratio - 1.0) / 0.5)      // green at goal → red at +50%
        let hue = 0.33 * min(max(position, 0), 1)    // 0 = red, 0.33 = green
        return Color(hue: hue, saturation: 0.85, brightness: 0.9)
    }
}
