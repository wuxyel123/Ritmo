import SwiftUI
import FitSyncCore

struct InsightCard: View {
    let insight: FitInsight

    var accentColor: Color {
        switch insight.type {
        case .warning: .orange; case .suggestion: .blue
        case .tip: .purple; case .positive: .green
        }
    }

    private var localizedMessage: String {
        let format = NSLocalizedString(insight.messageKey, comment: "")
        guard !insight.messageArgs.isEmpty else { return format }
        let args: [CVarArg] = insight.messageArgs.map { $0 as CVarArg }
        return String(format: format, arguments: args)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(insight.icon).font(.title3)
                Text(LocalizedStringKey(insight.title)).font(.subheadline.bold()).foregroundStyle(accentColor)
                Spacer()
                Text(LocalizedStringKey(insight.category.displayName))
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(accentColor)
            }
            Text(localizedMessage).font(.subheadline).foregroundStyle(FitSyncTheme.textSecondary)
        }
        .padding(FitSyncTheme.cardPadding)
        .background(FitSyncTheme.cardBG, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius)
            .stroke(accentColor.opacity(0.3), lineWidth: 1))
    }
}
