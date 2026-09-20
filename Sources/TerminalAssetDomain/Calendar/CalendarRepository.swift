import Foundation

public enum CalendarAuthorization: Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}

/// Abstraction over the system calendar. Views and the Context Engine depend on this, never on EventKit.
public protocol CalendarRepository: Sendable {
    func authorizationStatus() -> CalendarAuthorization

    /// Asks the user for full calendar access. Returns the resulting status rather than a bare Bool.
    func requestAccess() async throws -> CalendarAuthorization

    /// Occurrences overlapping `interval`. Throws `CalendarError.permissionDenied` (or a sibling) without access.
    func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot]

    /// Calendars that accept new events, for the "which calendar" choice. Throws without calendar access.
    func writableCalendars() async throws -> [CalendarInfo]

    /// Adds a one-off event and returns it as the calendar stored it. Throws `CalendarError.noWritableCalendar` or
    /// `.calendarNotFound` when there is nowhere to put it, and `.writeFailed` if the system rejects the save.
    func createEvent(_ event: ValidatedNewEvent) async throws -> CalendarEventSnapshot

    /// Emits whenever the system calendar changed. Coalesced: bursts collapse into a single element.
    func storeChanges() -> AsyncStream<Void>
}
