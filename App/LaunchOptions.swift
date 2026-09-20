import Foundation

enum AppTab: String, Hashable {
    case today, search, inbox, prep, settings
}

#if DEBUG
/// Debug-only launch arguments so CI can screenshot every screen without tapping.
/// Example: `-sampleData -tab search -query audit`.
enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var tab: AppTab? { defaults.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) }
    static var query: String { defaults.string(forKey: "query") ?? "" }
    static var showOnboarding: Bool { arguments.contains("-onboarding") }
    static var showPaywall: Bool { arguments.contains("-paywall") }
    static var openDetail: Bool { arguments.contains("-detail") }
    static var addSheet: String? { defaults.string(forKey: "addSheet") }
    static var prepDetail: Bool { arguments.contains("-prepDetail") }
    static var privacyDetail: Bool { arguments.contains("-privacy") }
    static var isSampleMode: Bool { arguments.contains("-sampleData") }
    /// `-weather rain` (any `WeatherCondition` raw value) shows a fixed sample forecast.
    static var weatherCondition: String? { defaults.string(forKey: "weather") }
    static var night: Bool { arguments.contains("-night") }
    /// Shows the "allow location" card instead of a forecast.
    static var weatherPermission: Bool { arguments.contains("-weatherPermission") }
    /// Uses the real location service and Open-Meteo instead of the sample forecast.
    static var liveWeather: Bool { arguments.contains("-liveWeather") }
    /// `-todaySection hourly|daily|details|widgets` scrolls Today to that section after it loads.
    static var todaySection: String? { defaults.string(forKey: "todaySection") }
    /// `-calendar month` or `-calendar day` opens the full calendar from Today.
    static var calendarMode: String? { defaults.string(forKey: "calendar") }
}
#endif
