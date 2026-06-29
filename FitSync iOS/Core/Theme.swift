import SwiftUI

enum FitSyncTheme {
    // Palette
    static let accent        = Color("AccentColor")
    #if os(iOS)
    static let background    = Color(uiColor: .systemBackground)
    static let cardBG        = Color(uiColor: .secondarySystemBackground)
    static let textPrimary   = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    #else
    static let background    = Color(nsColor: .windowBackgroundColor)
    static let cardBG        = Color(nsColor: .controlBackgroundColor)
    static let textPrimary   = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    #endif

    // Colori semantici
    static let calories  = Color.orange
    static let protein   = Color.red
    static let carbs     = Color.yellow
    static let fat       = Color.green
    static let fiber     = Color.mint
    static let water     = Color.blue
    static let sleep     = Color.indigo
    static let workout   = Color.purple
    static let steps     = Color.cyan
    static let positive  = Color.green
    static let warning   = Color.orange
    static let danger    = Color.red

    // Radii
    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 999

    // Spacing
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let gap: CGFloat = 12
}
