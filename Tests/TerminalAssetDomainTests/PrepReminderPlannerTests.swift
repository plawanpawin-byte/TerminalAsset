import Foundation
import Testing
@testable import TerminalAssetDomain

/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600

private func item(_ kind: ContextItemKind, done: Bool = false) -> ContextItemValue {
    ContextItemValue(id: UUID(), kind: kind, title: "x", detail: nil, url: nil, isDone: done, createdAt: now)
}

private func event(
    _ title: String,
    in offset: TimeInterval,
    allDay: Bool = false,
    state: SyncState = .active,
    items: [ContextItemValue] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"), title: title,
        startDate: now + offset, endDate: now + offset + hour,
        isAllDay: allDay, location: nil, syncState: state, items: items
    )
}

@Suite("PrepReminderPlanner")
struct PrepReminderPlannerTests {
    @Test func aReminderFiresFifteenMinutesBeforeAnEventWithOpenTasks() {
        let plan = PrepReminderPlanner.plan(
            from: [event("Audit", in: 2 * hour, items: [item(.task), item(.note)])], now: now
        )
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == now + 2 * hour - 15 * minute)
        #expect(plan[0].eventTitle == "Audit")
        #expect(plan[0].minutesBefore == 15)
        #expect(plan[0].preparation == .waiting(tasks: 1, notes: 1, links: 0, files: 0))
    }

    @Test func aQuietEventWithNothingAttachedGetsANudgeToAddContext() {
        let plan = PrepReminderPlanner.plan(from: [event("Kickoff", in: hour)], now: now)
        #expect(plan.count == 1)
        #expect(plan[0].preparation == .nothingAttached)
    }

    @Test func anEventWhoseTasksAreAllDoneIsLeftAlone() {
        let plan = PrepReminderPlanner.plan(
            from: [event("Done", in: hour, items: [item(.task, done: true)])], now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func anEventWithOnlyNotesOrLinksIsLeftAlone() {
        let plan = PrepReminderPlanner.plan(
            from: [event("Prepared", in: hour, items: [item(.note), item(.link)])], now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func pastAndAllDayAndMissingEventsAreSkipped() {
        let plan = PrepReminderPlanner.plan(
            from: [
                event("Past", in: -hour),
                event("AllDay", in: hour, allDay: true),
                event("Gone", in: hour, state: .missing)
            ],
            now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func eventsBeyondTheHorizonAreNotPlannedYet() {
        let plan = PrepReminderPlanner.plan(from: [event("Far", in: 72 * hour)], now: now)
        #expect(plan.isEmpty)
    }

    @Test func anImminentEventStillGetsAReminderShortlyFromNow() {
        let plan = PrepReminderPlanner.plan(from: [event("Soon", in: 5 * minute)], now: now)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == now + minute)
        #expect(plan[0].minutesBefore == 4)
    }

    @Test func anEventStartingWithinAMinuteIsNotWorthAReminder() {
        #expect(PrepReminderPlanner.plan(from: [event("Now", in: 30)], now: now).isEmpty)
    }

    @Test func remindersAreSortedAndLimited() {
        let events = (1...5).map { event("E\($0)", in: Double(6 - $0) * hour) }
        let plan = PrepReminderPlanner.plan(from: events, now: now, settings: .init(limit: 3))
        #expect(plan.map(\.eventKey.rawValue) == ["k-E5", "k-E4", "k-E3"])
    }

    @Test func idsAreStablePerEvent() {
        let first = PrepReminderPlanner.plan(from: [event("Audit", in: hour)], now: now)
        let later = PrepReminderPlanner.plan(from: [event("Audit", in: hour)], now: now + 5 * minute)
        #expect(first.first?.id == later.first?.id)
        #expect(first.first?.id.hasPrefix(PrepReminderPlanner.idPrefix) == true)
    }

    @Test func preparationCountsEachKindOfContext() {
        let plan = PrepReminderPlanner.plan(
            from: [event("Big", in: hour, items: [item(.task), item(.task), item(.link), item(.link), item(.file)])],
            now: now
        )
        #expect(plan.first?.preparation == .waiting(tasks: 2, notes: 0, links: 2, files: 1))
    }
}
