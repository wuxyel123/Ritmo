import SwiftUI
import FitSyncCore

// MARK: - Reusable Card Component
struct FitCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(FitSyncTheme.cardPadding)
            .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            if let action, let onAction {
                Button(LocalizedStringKey(action), action: onAction)
                    .font(.subheadline)
                    .foregroundStyle(FitSyncTheme.accent)
            }
        }
    }
}

// MARK: - Progress Bar
struct FitProgressBar: View {
    let value: Double   // 0-1
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(color.opacity(0.2))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: 999)
                    .fill(value >= 1 ? FitSyncTheme.positive : color)
                    .frame(width: geo.size.width * min(value, 1), height: height)
                    .animation(.spring(response: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Macro Row (used in Nutrition and Dashboard)
struct MacroRow: View {
    let emoji: String
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color
    var fractionDigits: Int = 0

    var progress: Double { min(current / max(goal, 1), 1.0) }
    // Bar color is derived from goal adherence (shared everywhere); the `color`
    // parameter is kept for call-site compatibility but no longer drives the bar.
    private var barColor: Color { NutritionScale.color(value: current, goal: goal) }

    private var formattedGoal: String {
        fractionDigits > 0
            ? String(format: "%.\(fractionDigits)f\(unit)", goal)
            : "\(Int(goal))\(unit)"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(emoji)
                Text(LocalizedStringKey(label))
                    .font(.subheadline)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                Spacer()
                HStack(spacing: 3) {
                    Text(current, format: .number.precision(.fractionLength(fractionDigits)))
                        .fontWeight(.semibold)
                        .foregroundStyle(progress >= 1 ? FitSyncTheme.positive : FitSyncTheme.textPrimary)
                    Text("/ \(formattedGoal)")
                        .font(.subheadline)
                        .foregroundStyle(FitSyncTheme.textSecondary)
                }
            }
            FitProgressBar(value: progress, color: barColor)
        }
    }
}

// MARK: - Empty Data View
struct EmptyDataView: View {
    let message: LocalizedStringKey
    var body: some View {
        Text(message)
            .font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding()
    }
}

// MARK: - View helpers
extension View {
    @ViewBuilder
    func applyIf<M: View>(_ condition: Bool, transform: (Self) -> M) -> some View {
        if condition { transform(self) } else { self }
    }
}
