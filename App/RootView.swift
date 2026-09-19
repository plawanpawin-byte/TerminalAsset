import SwiftUI
import TerminalAssetDomain

/// The app shell: first-run onboarding, then five tabs.
struct RootView: View {
    let app: AppModel

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab

    init(app: AppModel) {
        self.app = app
        #if DEBUG
        _selection = State(initialValue: LaunchOptions.tab ?? .today)
        #else
        _selection = State(initialValue: .today)
        #endif
    }

    var body: some View {
        Group {
            if showsOnboarding {
                OnboardingView { hasCompletedOnboarding = true }
            } else {
                tabs
            }
        }
        .task { await app.start() }
        .onChange(of: scenePhase) { _, phase in
            // Items shared while the app was closed are waiting in the queue.
            if phase == .active { Task { await app.inbox.refresh() } }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "calendar.day.timeline.left", value: AppTab.today) {
                TodayView(
                    model: app.today,
                    weather: app.weather,
                    initialPath: initialTodayPath,
                    initialCalendar: initialCalendarMode
                )
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(model: app.search, today: app.today)
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                InboxView(model: app.inbox)
            }
            .badge(app.inbox.items.count)
            Tab("Prep", systemImage: "sparkles", value: AppTab.prep) {
                PrepView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
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

    private var initialCalendarMode: CalendarViewModel.Mode? {
        #if DEBUG
        return LaunchOptions.calendarMode.flatMap(CalendarViewModel.Mode.init(rawValue:))
        #else
        return nil
        #endif
    }

    private var initialTodayPath: [EventKey] {
        #if DEBUG
        if LaunchOptions.openDetail { return [SampleData.auditKey()] }
        #endif
        return []
    }
}
