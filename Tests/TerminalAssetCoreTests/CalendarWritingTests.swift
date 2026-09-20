#if canImport(SwiftData)
import Foundation
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func newEvent(_ title: String = "Dentist", start: Date = base + hour) throws -> ValidatedNewEvent {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return try NewEventDraft(title: title, start: start, end: start + hour).validated(calendar: calendar)
}

@Suite("Adding events")
struct CalendarWritingTests {
    private func makeService(
        authorization: CalendarAuthorization = .fullAccess
    ) throws -> (CalendarSyncService, ContextStore) {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let service = CalendarSyncService(
            repository: StubCalendarRepository(snapshots: [], authorization: authorization),
            store: CalendarSyncActor(modelContainer: container)
        )
        return (service, ContextStore(modelContainer: container))
    }

    @Test func createdEventIsInTheAppImmediately() async throws {
        let (service, store) = try makeService()

        let key = try await service.createEvent(try newEvent())

        let events = try await store.events(from: base - day, to: base + 2 * day)
        #expect(events.map(\.key) == [key])
        #expect(events.first?.title == "Dentist")
    }

    @Test func syncingAgainDoesNotDuplicateTheCreatedEvent() async throws {
        let (service, store) = try makeService()
        let key = try await service.createEvent(try newEvent())

        try await service.sync(window: DateInterval(start: base - day, end: base + 2 * day))

        let events = try await store.events(from: base - day, to: base + 2 * day)
        #expect(events.map(\.key) == [key])
    }

    @Test func writableCalendarsListTheDefaultFirst() async throws {
        let (service, _) = try makeService()
        let calendars = try await service.writableCalendars()
        #expect(calendars.first?.isDefault == true)
    }

    @Test func permissionFailuresAreReportedAsSyncErrors() async throws {
        let (service, _) = try makeService(authorization: .denied)
        await #expect(throws: SyncError.calendar(.permissionDenied)) {
            try await service.createEvent(try newEvent())
        }
    }
}
#endif
