import Foundation

/// In-memory `CalendarRepository` for tests, previews and demo mode. Never touches EventKit.
public struct StubCalendarRepository: CalendarRepository {
    private let snapshots: [CalendarEventSnapshot]
    private let status: CalendarAuthorization

    public init(snapshots: [CalendarEventSnapshot], authorization: CalendarAuthorization = .fullAccess) {
        self.snapshots = snapshots
        self.status = authorization
    }

    public func authorizationStatus() -> CalendarAuthorization { status }

    public func requestAccess() async throws -> CalendarAuthorization { status }

    public func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot] {
        guard status == .fullAccess else { throw CalendarError.permissionDenied }
        return snapshots.filter { $0.startDate < interval.end && $0.endDate > interval.start }
    }

    /// A stream that finishes immediately: a stub calendar never changes.
    public func storeChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
