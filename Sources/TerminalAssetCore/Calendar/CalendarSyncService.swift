#if canImport(SwiftData)
import Foundation
import TerminalAssetDomain

/// Orchestrates permission check → EventKit fetch → SwiftData apply. Holds no UI state and touches no MainActor.
///
/// Offline/Degraded: this slice needs no network. If calendar access is missing it throws a typed
/// `SyncError.calendar` and leaves already-stored events and their context fully readable.
public actor CalendarSyncService {
    /// Default window: recent past (for "previous related events") through the near future.
    public static let defaultWindowDays: (past: Int, future: Int) = (30, 90)

    private let repository: any CalendarRepository
    private let store: CalendarSyncActor
    private let calendar: Calendar

    public init(repository: any CalendarRepository, store: CalendarSyncActor, calendar: Calendar = .current) {
        self.repository = repository
        self.store = store
        self.calendar = calendar
    }

    /// Current permission without prompting, so the UI can explain before it asks.
    public nonisolated func authorizationStatus() -> CalendarAuthorization {
        repository.authorizationStatus()
    }

    public func requestAccessIfNeeded() async throws -> CalendarAuthorization {
        let status = repository.authorizationStatus()
        guard status == .notDetermined else { return status }
        do {
            return try await repository.requestAccess()
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
    }

    @discardableResult
    public func syncNow(around date: Date = .now) async throws -> SyncReport {
        try await sync(window: makeWindow(around: date), now: date)
    }

    /// Syncs an arbitrary range, for example the month the calendar screen is showing. Events that vanished are
    /// only marked missing inside this range, so syncing a far-away month never touches other data.
    @discardableResult
    public func sync(window: DateInterval, now: Date = .now) async throws -> SyncReport {
        let snapshots: [CalendarEventSnapshot]
        do {
            snapshots = try await repository.events(in: window)
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
        return try await store.apply(snapshots: snapshots, window: window, now: now)
    }

    /// Calendars the user can add events to, default first.
    public func writableCalendars() async throws -> [CalendarInfo] {
        do {
            let calendars = try await repository.writableCalendars()
            return calendars.filter(\.isDefault) + calendars.filter { !$0.isDefault }
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
    }

    /// Writes the event to the system calendar, then syncs the days it covers so it is in the app straight away
    /// (with the same identity a later sync would give it, so nothing is duplicated). Returns that identity.
    @discardableResult
    public func createEvent(_ event: ValidatedNewEvent) async throws -> EventKey {
        let snapshot: CalendarEventSnapshot
        do {
            snapshot = try await repository.createEvent(event)
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
        let start = calendar.startOfDay(for: snapshot.startDate)
        let lastDay = calendar.startOfDay(for: max(snapshot.startDate, snapshot.endDate))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        // The event is already in the calendar, so a failure to copy it into the app must not look like a failed
        // add (the user would add it again and get a duplicate). The change notification syncs it a moment later.
        _ = try? await sync(window: DateInterval(start: start, end: max(start, end)))
        return EventIdentity.key(for: snapshot, calendar: calendar)
    }

    /// Syncs once, then again on every (coalesced) calendar change until the task is cancelled.
    /// `onSynced` fires after every successful sync; a failed sync is reported through `onFailure`
    /// and does not stop observation.
    public func keepInSync(
        onSynced: @Sendable (SyncReport) -> Void,
        onFailure: @Sendable (SyncError) -> Void
    ) async {
        await syncAndReport(onSynced: onSynced, onFailure: onFailure)
        for await _ in repository.storeChanges() {
            if Task.isCancelled { return }
            await syncAndReport(onSynced: onSynced, onFailure: onFailure)
        }
    }

    private func syncAndReport(
        onSynced: @Sendable (SyncReport) -> Void,
        onFailure: @Sendable (SyncError) -> Void
    ) async {
        do {
            onSynced(try await syncNow())
        } catch let error as SyncError {
            onFailure(error)
        } catch {
            onFailure(.persistence(reason: error.localizedDescription))
        }
    }

    private func makeWindow(around date: Date) -> DateInterval {
        let past = calendar.date(byAdding: .day, value: -Self.defaultWindowDays.past, to: date) ?? date
        let future = calendar.date(byAdding: .day, value: Self.defaultWindowDays.future, to: date) ?? date
        return DateInterval(start: past, end: future)
    }
}
#endif
