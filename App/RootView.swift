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
        .task {
            await app.start()
            openPendingSearch()
        }
        // Keeps prep reminders and the home-screen widget in step with the calendar, whichever tab is showing.
        .onChange(of: app.today.events) { _, events in
            Task {
                await app.reminders.refresh(events: events)
                await app.widgets.publish()
            }
        }
        // A tapped reminder or widget opens its event on the Today tab.
        .onOpenURL { url in
            if let link = DeepLink(url: url) { app.router.open(link) }
        }
        .onChange(of: app.router.pendingEvent, initial: true) { _, pending in
            if pending != nil { selection = .today }
        }
        .onChange(of: scenePhase) { _, phase in
            // Items shared while the app was closed are waiting in the queue.
            if phase == .active {
                Task { await app.inbox.refresh() }
                openPendingSearch()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "calendar.day.timeline.left", value: AppTab.today) {
                TodayView(
                    model: app.today,
                    looseEnds: app.looseEnds,
                    router: app.router,
                    weather: app.weather,
                    initialPath: initialTodayPath,
                    initialCalendar: initialCalendarMode
                )
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack {
                    CalendarScreen(today: app.today, mode: .month)
                        .navigationDestination(for: EventKey.self) { key in
                            EventDetailView(key: key, today: app.today)
                        }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(model: app.search, today: app.today)
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                InboxView(model: app.inbox)
            }
            .badge(app.inbox.items.count)
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(model: app.settings, reminders: app.reminders)
            }
        }
    }

    /// "Find context" from Siri or Shortcuts leaves its words behind; show them in Search.
    private func openPendingSearch() {
        guard let query = PendingSearch.take() else { return }
        selection = .search
        app.search.query = query
        app.search.scheduleSearch()
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
