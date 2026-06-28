import SwiftUI

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case system      = "system"
    case italian     = "it"
    case english     = "en"
    case french      = "fr"
    case portuguese  = "pt"
    case german      = "de"
    case spanish     = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:     return "Automatico (Sistema)"
        case .italian:    return "Italiano"
        case .english:    return "English"
        case .french:     return "Français"
        case .portuguese: return "Português"
        case .german:     return "Deutsch"
        case .spanish:    return "Español"
        }
    }

    var flagEmoji: String {
        switch self {
        case .system:     return "🌐"
        case .italian:    return "🇮🇹"
        case .english:    return "🇬🇧"
        case .french:     return "🇫🇷"
        case .portuguese: return "🇵🇹"
        case .german:     return "🇩🇪"
        case .spanish:    return "🇪🇸"
        }
    }

    var locale: Locale {
        if self == .system { return .autoupdatingCurrent }
        return Locale(identifier: rawValue)
    }

    // The locale code to use for bundle lookups
    var resolvedCode: String {
        if self == .system {
            return Locale.current.language.languageCode?.identifier ?? "it"
        }
        return rawValue
    }
}

// MARK: - LanguageManager

final class LanguageManager: ObservableObject {
    static let storageKey = "appLanguage"

    @Published private(set) var language: AppLanguage
    @Published private(set) var viewID = UUID()

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: saved) ?? .system
    }

    func set(_ lang: AppLanguage) {
        guard lang != language else { return }
        UserDefaults.standard.set(lang.rawValue, forKey: Self.storageKey)
        language = lang
        viewID = UUID()
    }

    var locale: Locale { language.locale }
}
