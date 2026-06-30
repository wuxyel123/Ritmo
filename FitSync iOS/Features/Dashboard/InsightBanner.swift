import SwiftUI
import FitSyncCore

struct InsightBanner: View {
    let insight: FitInsight

    var bgColor: Color {
        switch insight.type {
        case .warning: return .orange.opacity(0.12)
        case .suggestion: return .blue.opacity(0.12)
        case .tip: return .purple.opacity(0.12)
        case .positive: return .green.opacity(0.12)
        }
    }

    var accentColor: Color {
        switch insight.type {
        case .warning: return .orange
        case .suggestion: return .blue
        case .tip: return .purple
        case .positive: return .green
        }
    }

    private var localizedMessage: String {
        let format = NSLocalizedString(insight.messageKey, comment: "")
        guard !insight.messageArgs.isEmpty else { return format }
        let args: [CVarArg] = insight.messageArgs.map { $0 as CVarArg }
        return String(format: format, arguments: args)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(insight.icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(insight.title))
                    .font(.subheadline.bold())
                    .foregroundStyle(accentColor)
                Text(localizedMessage)
                    .font(.caption)
                    .foregroundStyle(FitSyncTheme.textSecondary)
                    .lineLimit(3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(FitSyncTheme.cardPadding)
        .background(bgColor, in: RoundedRectangle(cornerRadius: FitSyncTheme.cardRadius))
    }
}
