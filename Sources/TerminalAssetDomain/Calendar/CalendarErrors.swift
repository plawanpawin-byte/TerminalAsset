import Foundation

public enum CalendarError: Error, Sendable, Equatable {
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    /// The user granted write-only access, which cannot be used to read events.
    case writeOnlyAccess
    case eventNotFound
    case storeUnavailable(reason: String)
    /// No calendar on this device accepts new events (for example every calendar is read-only).
    case noWritableCalendar
    /// The chosen calendar no longer exists or cannot be changed.
    case calendarNotFound
    case writeFailed(reason: String)
}

public enum SyncError: Error, Sendable, Equatable {
    case calendar(CalendarError)
    case persistence(reason: String)
}
