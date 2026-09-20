#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
private let window = DateInterval(start: base - 30 * day, end: base + 90 * day)

private func snapshot(
    title: String = "ISO Audit Prep",
    start: Date = base,
    occurrence: Date? = nil
) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: "series-evt",
        externalIdentifier: "series",
        calendarID: "cal-1",
        title: title,
        startDate: start,
        endDate: start + hour,
        occurrenceDate: occurrence ?? start,
        isAllDay: false,
        location: nil,
        isRecurring: true
    )
}

@Suite("CalendarSyncActor")
struct CalendarSyncActorTests {
    private func makeActor() throws -> (CalendarSyncActor, ModelContainer) {
        let container = try TemporalStore.makeContainer(inMemory: true)
        return (CalendarSyncActor(modelContainer: container), container)
    }

    @Test func insertingAnEventCreatesItsContext() async throws {
        let (actor, container) = try makeActor()

        let report = try await actor.apply(snapshots: [snapshot()], window: window, now: base)

        #expect(report.inserted == 1)
        let events = try ModelContext(container).fetch(FetchDescriptor<TemporalEvent>())
        #expect(events.count == 1)
        #expect(events.first?.context != nil)
    }

    @Test func movedOccurrenceKeepsTheSameRecordAndContext() async throws {
        let (actor, container) = try makeActor()
        _ = try await actor.apply(snapshots: [snapshot()], window: window, now: base)
        let contextCreatedAt = try ModelContext(container).fetch(FetchDescriptor<TemporalContext>()).first?.createdAt

        let moved = snapshot(start: base + 2 * hour, occurrence: base)
        let report = try await actor.apply(snapshots: [moved], window: window, now: base + hour)

        #expect(report.inserted == 0)
        #expect(report.updated == 1)
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<TemporalEvent>())
        #expect(events.count == 1)
        #expect(events.first?.startDate == base + 2 * hour)
        #expect(try context.fetch(FetchDescriptor<TemporalContext>()).first?.createdAt == contextCreatedAt)
    }

    @Test func disappearedEventIsKeptAsMissingThenRestored() async throws {
        let (actor, container) = try makeActor()
        _ = try await actor.apply(snapshots: [snapshot()], window: window, now: base)

        let gone = try await actor.apply(snapshots: [], window: window, now: base + hour)
        #expect(gone.markedMissing == 1)
        let afterGone = try ModelContext(container).fetch(FetchDescriptor<TemporalEvent>())
        #expect(afterGone.count == 1)
        #expect(afterGone.first?.syncState == .missing)
        #expect(afterGone.first?.context != nil)

        let back = try await actor.apply(snapshots: [snapshot()], window: window, now: base + 2 * hour)
        #expect(back.restored == 1)
        let afterBack = try ModelContext(container).fetch(FetchDescriptor<TemporalEvent>())
        #expect(afterBack.count == 1)
        #expect(afterBack.first?.syncState == .active)
    }

    @Test func repeatedSyncIsIdempotent() async throws {
        let (actor, container) = try makeActor()
        _ = try await actor.apply(snapshots: [snapshot()], window: window, now: base)
        let second = try await actor.apply(snapshots: [snapshot()], window: window, now: base + hour)

        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(second.markedMissing == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TemporalEvent>()) == 1)
    }
}
#endif
