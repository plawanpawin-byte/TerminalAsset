import Foundation

public enum CalendarError: Error, Sendable, Equatable {
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    /// The user granted write-only access, which cannot be used to read events.
    case writeOnlyAccess
    case eventNotFound
    case storeUnavailable(reason: String)
}

public enum SyncError: Error, Sendable, Equatable {
    case calendar(CalendarError)
    case persistence(reason: String)
}
