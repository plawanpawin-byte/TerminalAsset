#if canImport(EventKit)
import EventKit
import Foundation
import TerminalAssetDomain

/// EventKit-backed `CalendarRepository`. The `EKEventStore` never leaves this actor;
/// callers only ever receive `CalendarEventSnapshot` values.
public actor EventKitRepository: CalendarRepository {
    /// `EKEventStore` is not annotated `Sendable`, but the store is owned by this actor, never handed out,
    /// and Apple documents it as safe to call from any thread, so awaiting its async API from here is safe.
    private nonisolated(unsafe) let store = EKEventStore()

    public init() {}

    public nonisolated func authorizationStatus() -> CalendarAuthorization {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async throws -> CalendarAuthorization {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            throw CalendarError.storeUnavailable(reason: error.localizedDescription)
        }
        return authorizationStatus()
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot] {
        try Self.requireReadAccess(authorizationStatus())
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.snapshot(from:))
    }

    public func writableCalendars() async throws -> [CalendarInfo] {
        try Self.requireWriteAccess(authorizationStatus())
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, isDefault: $0.calendarIdentifier == defaultID) }
    }

    public func createEvent(_ newEvent: ValidatedNewEvent) async throws -> CalendarEventSnapshot {
        try Self.requireWriteAccess(authorizationStatus())

        let target: EKCalendar
        if let id = newEvent.calendarID {
            guard let chosen = store.calendar(withIdentifier: id), chosen.allowsContentModifications else {
                throw CalendarError.calendarNotFound
            }
            target = chosen
        } else if let fallback = store.defaultCalendarForNewEvents, fallback.allowsContentModifications {
            target = fallback
        } else if let any = store.calendars(for: .event).first(where: \.allowsContentModifications) {
            target = any
        } else {
            throw CalendarError.noWritableCalendar
        }

        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = newEvent.title
        event.isAllDay = newEvent.isAllDay
        event.startDate = newEvent.start
        event.endDate = newEvent.end
        event.location = newEvent.location

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.writeFailed(reason: error.localizedDescription)
        }
        guard let snapshot = Self.snapshot(from: event) else {
            throw CalendarError.writeFailed(reason: "The saved event has no dates.")
        }
        return snapshot
    }

    public nonisolated func storeChanges() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Mapping

    private static func snapshot(from event: EKEvent) -> CalendarEventSnapshot? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        return CalendarEventSnapshot(
            eventIdentifier: event.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            startDate: start,
            endDate: end,
            occurrenceDate: event.occurrenceDate ?? start,
            isAllDay: event.isAllDay,
            location: event.location,
            isRecurring: event.hasRecurrenceRules || event.isDetached
        )
    }

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        default: .denied
        }
    }

    /// Writing works with full access and with write-only access.
    private static func requireWriteAccess(_ status: CalendarAuthorization) throws {
        switch status {
        case .fullAccess, .writeOnly: return
        case .notDetermined: throw CalendarError.permissionNotDetermined
        case .restricted: throw CalendarError.permissionRestricted
        case .denied: throw CalendarError.permissionDenied
        }
    }

    private static func requireReadAccess(_ status: CalendarAuthorization) throws {
        switch status {
        case .fullAccess: return
        case .notDetermined: throw CalendarError.permissionNotDetermined
        case .restricted: throw CalendarError.permissionRestricted
        case .denied: throw CalendarError.permissionDenied
        case .writeOnly: throw CalendarError.writeOnlyAccess
        }
    }
}
#endif
