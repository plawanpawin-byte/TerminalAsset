#if canImport(EventKit)
import EventKit
import Foundation
import TerminalAssetDomain

/// EventKit-backed `CalendarRepository`. The `EKEventStore` never leaves this actor;
/// callers only ever receive `CalendarEventSnapshot` values.
public actor EventKitRepository: CalendarRepository {
    private let store = EKEventStore()

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
