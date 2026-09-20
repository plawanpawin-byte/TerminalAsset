import Foundation

/// In-memory `CalendarRepository` for tests, previews and demo mode. Never touches EventKit. Events created
/// through it live only as long as the stub does.
public actor StubCalendarRepository: CalendarRepository {
    public static let defaultCalendars = [
        CalendarInfo(id: "stub.personal", title: "Personal", isDefault: true),
        CalendarInfo(id: "stub.work", title: "Work", isDefault: false)
    ]

    private var snapshots: [CalendarEventSnapshot]
    private let status: CalendarAuthorization
    private let calendars: [CalendarInfo]

    public init(
        snapshots: [CalendarEventSnapshot],
        authorization: CalendarAuthorization = .fullAccess,
        calendars: [CalendarInfo] = StubCalendarRepository.defaultCalendars
    ) {
        self.snapshots = snapshots
        self.status = authorization
        self.calendars = calendars
    }

    public nonisolated func authorizationStatus() -> CalendarAuthorization { status }

    public func requestAccess() async throws -> CalendarAuthorization { status }

    public func events(in interval: DateInterval) async throws -> [CalendarEventSnapshot] {
        guard status == .fullAccess else { throw CalendarError.permissionDenied }
        return snapshots.filter { $0.startDate < interval.end && $0.endDate > interval.start }
    }

    public func writableCalendars() async throws -> [CalendarInfo] {
        try requireWriteAccess()
        return calendars
    }

    public func createEvent(_ event: ValidatedNewEvent) async throws -> CalendarEventSnapshot {
        try requireWriteAccess()
        guard !calendars.isEmpty else { throw CalendarError.noWritableCalendar }

        let target: CalendarInfo
        if let id = event.calendarID {
            guard let match = calendars.first(where: { $0.id == id }) else { throw CalendarError.calendarNotFound }
            target = match
        } else {
            target = calendars.first(where: \.isDefault) ?? calendars[0]
        }

        let identifier = "stub-\(UUID().uuidString)"
        let snapshot = CalendarEventSnapshot(
            eventIdentifier: identifier,
            externalIdentifier: identifier,
            calendarID: target.id,
            title: event.title,
            startDate: event.start,
            endDate: event.end,
            occurrenceDate: event.start,
            isAllDay: event.isAllDay,
            location: event.location,
            isRecurring: false
        )
        snapshots.append(snapshot)
        return snapshot
    }

    /// A stream that finishes immediately: a stub calendar only changes through its own `createEvent`.
    public nonisolated func storeChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    private func requireWriteAccess() throws {
        switch status {
        case .fullAccess, .writeOnly: return
        case .notDetermined: throw CalendarError.permissionNotDetermined
        case .restricted: throw CalendarError.permissionRestricted
        case .denied: throw CalendarError.permissionDenied
        }
    }
}
