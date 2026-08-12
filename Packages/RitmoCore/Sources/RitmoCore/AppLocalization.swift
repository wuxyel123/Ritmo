import Foundation

// MARK: - AppLocalization
//
// SwiftUI's `Text(LocalizedStringKey(...))` resolves against the locale in the
// environment, which the app overrides from the in-app language picker. Plain
// `NSLocalizedString(...)` does not: it always reads `Bundle.main` in the
// SYSTEM language. So any user-facing string built as a Swift String — the
// daily recommendation's reason, the meet countdown, error messages — silently
// ignored the picker and came out in whatever language the phone was set to.
// That is why a card's title could be translated while its body was not.
//
// Everything that builds a String for display goes through here instead.

public enum AppLocalization {

    /// Key written by the app's LanguageManager.
    public static let languageKey = "appLanguage"
    private static let appGroupID = "group.alessandrodiscalzi.com.ritmo"

    /// The picked language code, or nil for "system".
    ///
    /// Read from standard defaults first (the app itself), then the App Group
    /// — widgets and the Watch app are separate processes with their own
    /// defaults domain, so without the shared copy a complication would keep
    /// speaking the system language while the app spoke the chosen one.
    private static var selectedCode: String? {
        let code = UserDefaults.standard.string(forKey: languageKey)
            ?? UserDefaults(suiteName: appGroupID)?.string(forKey: languageKey)
        guard let code, code != "system" else { return nil }
        return code
    }

    /// Bundle for the language the user picked, or `.main` when on "system".
    public static var bundle: Bundle {
        guard let code = selectedCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return .main }
        return localized
    }

    /// Called by the app when the picker changes, so the other processes see it.
    public static func share(languageCode: String) {
        UserDefaults(suiteName: appGroupID)?.set(languageCode, forKey: languageKey)
    }

    public static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Convenience for the common `String(format: localized, args…)` shape.
    public static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }
}
