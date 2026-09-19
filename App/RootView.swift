import SwiftUI
import TerminalAssetDomain

/// The app shell: first-run onboarding, then five tabs.
struct RootView: View {
    let model: TodayViewModel

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: AppTab
    @State private var inbox = InboxViewModel(items: UIFixtures.inboxItems(now: .now))

    init(model: TodayViewModel) {
        self.model = model
        #if DEBUG
        _selection = State(initialValue: LaunchOptions.tab ?? .today)
        #else
        _selection = State(initialValue: .today)
        #endif
    }

    var body: some View {
        if showsOnboarding {
            OnboardingView { hasCompletedOnboarding = true }
        } else {
            TabView(selection: $selection) {
                Tab("Today", systemImage: "calendar.day.timeline.left", value: AppTab.today) {
                    TodayView(model: model, initialPath: initialTodayPath)
                }
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                    SearchView()
                }
                Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                    InboxView(model: inbox)
                }
                .badge(inbox.items.count)
                Tab("Prep", systemImage: "sparkles", value: AppTab.prep) {
                    PrepView()
                }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
        }
    }

    private var showsOnboarding: Bool {
        #if DEBUG
        if LaunchOptions.showOnboarding { return true }
        if LaunchOptions.isSampleMode { return false }
        #endif
        return !hasCompletedOnboarding
    }

    private var initialTodayPath: [EventKey] {
        #if DEBUG
        if LaunchOptions.openDetail { return [SampleData.auditKey()] }
        #endif
        return []
    }
}
