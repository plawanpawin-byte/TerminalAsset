import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class TodayViewModel {
    enum Phase: Equatable {
        case loading
        case needsPermission(CalendarAuthorization)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var events: [TimelineEvent] = []
    /// Set when a refresh failed but previously loaded data is still shown.
    private(set) var problem: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let prepare: (@Sendable () async -> Void)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?

    init(
        sync: CalendarSyncService,
        store: ContextStore,
        calendar: Calendar = .current,
        prepare: (@Sendable () async -> Void)? = nil
    ) {
        self.sync = sync
        self.store = store
        self.calendar = calendar
        self.prepare = prepare
    }

    // MARK: - Reading

    func snapshot(at now: Date) -> TodaySnapshot {
        TodayTimeline.build(events: events, now: now, calendar: calendar)
    }

    // MARK: - Lifecycle

    /// Safe to call from several places: the first call does the work and every caller waits for it to finish.
    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { await performStart() }
        startTask = task
        await task.value
    }

    private func performStart() async {
        if let prepare { await prepare() }
        let status = sync.authorizationStatus()
        guard status == .fullAccess else {
            phase = .needsPermission(status)
            return
        }
        await beginSync()
    }

    func requestAccess() async {
        do {
            let status = try await sync.requestAccessIfNeeded()
            guard status == .fullAccess else {
                phase = .needsPermission(status)
                return
            }
            await beginSync()
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Called when the app returns to the foreground: picks up a permission change made in Settings.
    func didBecomeActive() async {
        switch phase {
        case .needsPermission:
            if sync.authorizationStatus() == .fullAccess { await beginSync() }
        case .ready, .failed:
            await reload()
        case .loading:
            break
        }
    }

    func reload(now: Date = .now) async {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        do {
            events = try await store.events(from: start, to: end)
            phase = .ready
            problem = nil
        } catch {
            let message = Self.message(for: error)
            if phase == .ready { problem = message } else { phase = .failed(message) }
        }
    }

    // MARK: - Actions

    func setTask(_ id: UUID, done: Bool) async {
        do {
            try await store.setTaskDone(id: id, isDone: done)
            await reload()
        } catch {
            problem = Self.message(for: error)
        }
    }

    func makeCalendarModel(mode: CalendarViewModel.Mode) -> CalendarViewModel {
        CalendarViewModel(sync: sync, store: store, mode: mode, calendar: calendar)
    }

    /// `onCreated` runs after Today has reloaded, with the start of the new event.
    func makeAddEventModel(day: Date, onCreated: @escaping @MainActor (Date) async -> Void) -> AddEventViewModel {
        AddEventViewModel(sync: sync, calendar: calendar, day: day) { [weak self] start in
            await self?.reload()
            await onCreated(start)
        }
    }

    func makeDetailModel(for key: EventKey) -> EventDetailViewModel {
        EventDetailViewModel(key: key, store: store) { [weak self] in
            await self?.reload()
        }
    }

    // MARK: - Private

    /// Shows what is already stored first (local-first), then syncs with the calendar.
    private func beginSync() async {
        await reload()
        guard syncTask == nil else { return }
        syncTask = Task { [sync] in
            await sync.keepInSync(
                onSynced: { [weak self] _ in
                    Task { @MainActor in await self?.reload() }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in self?.problem = Self.message(for: error) }
                }
            )
        }
    }

    nonisolated static func message(for error: Error) -> String {
        switch error {
        case let error as SyncError:
            switch error {
            case .calendar(let calendarError): return message(for: calendarError)
            case .persistence: return "Couldn't update the data saved on this device."
            }
        case let error as CalendarError:
            return message(for: error)
        case is ContextStoreError:
            return "Couldn't read your saved context."
        default:
            return "Something went wrong. Please try again."
        }
    }

    private nonisolated static func message(for error: CalendarError) -> String {
        switch error {
        case .permissionNotDetermined, .permissionDenied, .permissionRestricted, .writeOnlyAccess:
            return "Calendar access is off. Turn it on in Settings to see your day."
        case .eventNotFound:
            return "That event is no longer in your calendar."
        case .storeUnavailable:
            return "Your calendar isn't available right now."
        case .noWritableCalendar:
            return "None of your calendars can take new events."
        case .calendarNotFound:
            return "That calendar is no longer available. Choose another one."
        case .writeFailed:
            return "Couldn't save the event to your calendar. Please try again."
        }
    }
}
