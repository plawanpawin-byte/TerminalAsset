import Foundation
import TerminalAssetCore
import TerminalAssetDomain
import UserNotifications

struct BootstrapFailure: Error {
    let message: String
}

/// Everything the UI needs, built once at launch.
@MainActor
struct AppModel {
    let today: TodayViewModel
    let inbox: InboxViewModel
    let search: SearchViewModel
    let briefing: BriefingViewModel
    let settings: SettingsViewModel
    let reminders: PrepReminderViewModel
    let widgets: WidgetPublisher
    let router: AppRouter
    let weather: WeatherViewModel

    /// Loads Today, then imports shared items (they may auto-attach to events, so events must exist first).
    func start() async {
        await today.start()
        await inbox.refresh()
        await widgets.publish()
    }
}

/// Composition root: the only place that knows which concrete repository and store back the app.
@MainActor
enum AppBootstrap {
    private static var notificationDelegate: NotificationDelegate?

    static func make() -> Result<AppModel, BootstrapFailure> {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sampleData") {
                return .success(try makeSampleModel())
            }
            #endif
            let container = try TemporalStore.makeContainer()
            let sync = CalendarSyncService(
                repository: EventKitRepository(),
                store: CalendarSyncActor(modelContainer: container)
            )
            let store = ContextStore(modelContainer: container)
            // Without the App Group container (missing entitlement) sharing is off; the rest of the app works.
            let shared = try? SharedInbox.appGroup()
            let model = makeModel(
                sync: sync, store: store, shared: shared, weather: makeLiveWeather(),
                scheduler: UserNotificationScheduler()
            )
            // The center keeps only a weak reference, so the delegate lives for the whole run.
            notificationDelegate = NotificationDelegate(router: model.router)
            UNUserNotificationCenter.current().delegate = notificationDelegate
            return .success(model)
        } catch {
            return .failure(BootstrapFailure(message: String(localized: "The local data store could not be opened on this device.")))
        }
    }

    static func makeLiveWeather() -> WeatherViewModel {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("weather.json")
        let service = WeatherService(provider: OpenMeteoWeatherProvider(), cacheURL: cache)
        return WeatherViewModel(location: CoreLocationService(), service: service)
    }

    private static func makeModel(
        sync: CalendarSyncService,
        store: ContextStore,
        shared: SharedInbox?,
        weather: WeatherViewModel,
        scheduler: any ReminderScheduler,
        prepare: (@Sendable () async -> Void)? = nil
    ) -> AppModel {
        let today = TodayViewModel(sync: sync, store: store, prepare: prepare)
        let inbox = InboxViewModel(store: store, shared: shared) { [today] in
            await today.reload()
        }
        #if DEBUG
        let search = SearchViewModel(store: store, query: LaunchOptions.query)
        #else
        let search = SearchViewModel(store: store)
        #endif
        let briefing = BriefingViewModel(sync: sync, store: store)
        let widgets = WidgetPublisher(store: store, directory: shared?.rootURL)
        let settings = SettingsViewModel(sync: sync, store: store, shared: shared) { [today, inbox, search, briefing] in
            search.clearRecentSearches()
            await today.reload()
            await inbox.refresh()
            await briefing.load()
            await search.loadCorpus()
            await widgets.publish()
        }
        let reminders = PrepReminderViewModel(scheduler: scheduler)
        return AppModel(
            today: today, inbox: inbox, search: search, briefing: briefing, settings: settings,
            reminders: reminders, widgets: widgets, router: AppRouter(), weather: weather
        )
    }

    #if DEBUG
    /// In-memory database, stub calendar, seeded context and a temporary share queue. The queued items go through
    /// the same ingestion path as real shares. Used by previews and `-sampleData` launches.
    static func makeSampleModel(now: Date = SampleData.launchTime) throws -> AppModel {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncService(
            repository: StubCalendarRepository(snapshots: SampleData.snapshots(now: now)),
            store: CalendarSyncActor(modelContainer: container)
        )
        let store = ContextStore(modelContainer: container)
        let shared = SharedInbox(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TerminalAssetSample-\(UUID().uuidString)", isDirectory: true)
        )
        let weather = LaunchOptions.liveWeather ? makeLiveWeather() : SampleData.weatherModel(now: now)
        return makeModel(
            sync: sync, store: store, shared: shared, weather: weather,
            scheduler: InMemoryReminderScheduler(status: .notDetermined)
        ) {
            await SampleData.seed(sync: sync, store: store, shared: shared, now: now)
        }
    }
    #endif
}
