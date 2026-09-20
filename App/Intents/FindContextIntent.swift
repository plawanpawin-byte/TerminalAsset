import AppIntents
import Foundation

/// "Find context": searches what is attached to the user's events, from Siri, Spotlight or the Shortcuts app.
/// It opens the app on the Search tab with the words filled in, so the search runs on the device like any other.
struct FindContextIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Context"
    static let description = IntentDescription("Searches the notes, links and tasks attached to your events.")
    static let openAppWhenRun = true

    @Parameter(title: "Search", requestValueDialog: "What do you want to find?")
    var query: String

    func perform() async throws -> some IntentResult {
        PendingSearch.store(query)
        return .result()
    }
}

struct TerminalAssetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindContextIntent(),
            phrases: [
                "Find context in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Find Context",
            systemImageName: "magnifyingglass"
        )
    }
}

/// Hands the words from the intent to the app. Both run in the same process, so a plain default is enough; the app
/// takes it (and clears it) the next time it becomes active.
enum PendingSearch {
    private static let key = "intent.pendingSearch"

    static func store(_ query: String, defaults: UserDefaults = .standard) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: key)
    }

    static func take(defaults: UserDefaults = .standard) -> String? {
        guard let query = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return query
    }
}
