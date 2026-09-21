import Foundation

/// The languages the app is translated into, plus "follow the system".
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case thai

    var id: String { rawValue }

    /// The language identifier iOS should prefer for this app, or nil to follow the iPhone's language.
    var identifier: String? {
        switch self {
        case .system: nil
        case .english: "en-GB"
        case .thai: "th"
        }
    }

    /// Each language is named in itself and never translated: someone who cannot read the current language must still
    /// be able to find their own.
    var title: String {
        switch self {
        case .system: String(localized: "System default")
        case .english: "English (United Kingdom)"
        case .thai: "ไทย (ประเทศไทย)"
        }
    }
}

/// Remembers the chosen language and hands it to iOS, which reads it when the app next launches (the same
/// mechanism as Settings > TerminalAsset > Language). The choice applies to this app only.
struct LanguagePreference {
    static let key = "appLanguage"
    private static let systemKey = "AppleLanguages"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: AppLanguage {
        defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func choose(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
        if let identifier = language.identifier {
            defaults.set([identifier], forKey: Self.systemKey)
        } else {
            // No override: the app goes back to the iPhone's own language order.
            defaults.removeObject(forKey: Self.systemKey)
        }
    }
}
