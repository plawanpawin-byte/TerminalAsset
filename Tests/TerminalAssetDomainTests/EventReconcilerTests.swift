import Foundation
import Testing
@testable import TerminalAssetDomain

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
private let window = DateInterval(start: base - 30 * day, end: base + 90 * day)

private func snapshot(
    eventIdentifier: String? = "evt-1",
    external: String? = "ext-1",
    calendar: String = "cal-1",
    title: String = "ISO Audit Prep",
    start: Date = base,
    occurrence: Date? = nil,
    recurring: Bool = false
) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: eventIdentifier,
        externalIdentifier: external,
        calendarID: calendar,
        title: title,
        startDate: start,
        endDate: start + hour,
        occurrenceDate: occurrence ?? start,
        isAllDay: false,
        location: nil,
        isRecurring: recurring
    )
}

private func record(
    from snapshot: CalendarEventSnapshot,
    state: SyncState = .active
) -> StoredEventRecord {
    StoredEventRecord(
        key: EventIdentity.key(for: snapshot),
        lastEventIdentifier: snapshot.eventIdentifier,
        fingerprint: EventIdentity.fingerprint(for: snapshot),
        isRecurring: snapshot.isRecurring,
        startDate: snapshot.startDate,
        endDate: snapshot.endDate,
        state: state
    )
}

private func allDay(_ start: Date, external: String = "series", recurring: Bool = true) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: "evt", externalIdentifier: external, calendarID: "cal", title: "Holiday",
        startDate: start, endDate: start + 86_400, occurrenceDate: start,
        isAllDay: true, location: nil, isRecurring: recurring
    )
}

@Suite("All-day identity")
struct AllDayIdentityTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    @Test func anAllDayKeySurvivesATimeZoneChange() {
        let bangkok = calendar("Asia/Bangkok")
        let newYork = calendar("America/New_York")
        // "15 January 2027", as EventKit reports it before and after the device moves: local midnight each time.
        let inBangkok = allDay(bangkok.date(from: DateComponents(year: 2027, month: 1, day: 15)) ?? .distantPast)
        let inNewYork = allDay(newYork.date(from: DateComponents(year: 2027, month: 1, day: 15)) ?? .distantPast)
        #expect(inBangkok.startDate != inNewYork.startDate)

        #expect(EventIdentity.key(for: inBangkok, calendar: bangkok) == EventIdentity.key(for: inNewYork, calendar: newYork))
        #expect(
            EventIdentity.fingerprint(for: inBangkok, calendar: bangkok)
                == EventIdentity.fingerprint(for: inNewYork, calendar: newYork)
        )
    }

    @Test func anAllDayKeyDoesNotDependOnTheCalendarSystem() {
        // A Thai device uses the Buddhist calendar, where 2027 CE is year 2570. Switching region settings must not
        // change the key, or the event's context would be orphaned.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .gmt
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = gregorian.timeZone
        let day = allDay(gregorian.date(from: DateComponents(year: 2027, month: 1, day: 15)) ?? .distantPast)

        let key = EventIdentity.key(for: day, calendar: gregorian)
        #expect(EventIdentity.key(for: day, calendar: buddhist) == key)
        #expect(key.rawValue == "ext:series|d2027-1-15")
    }

    @Test func differentDaysOfTheSameSeriesStayDistinct() {
        let utc = calendar("UTC")
        let first = allDay(utc.date(from: DateComponents(year: 2027, month: 1, day: 15)) ?? .distantPast)
        let second = allDay(utc.date(from: DateComponents(year: 2027, month: 1, day: 16)) ?? .distantPast)
        #expect(EventIdentity.key(for: first, calendar: utc) != EventIdentity.key(for: second, calendar: utc))
    }

    @Test func aTimedEventStillUsesItsInstant() {
        let bangkok = calendar("Asia/Bangkok")
        let newYork = calendar("America/New_York")
        let timed = CalendarEventSnapshot(
            eventIdentifier: "e", externalIdentifier: "x", calendarID: "cal", title: "Standup",
            startDate: Date(timeIntervalSince1970: 1_800_000_000), endDate: Date(timeIntervalSince1970: 1_800_003_600),
            occurrenceDate: Date(timeIntervalSince1970: 1_800_000_000), isAllDay: false, location: nil, isRecurring: false
        )
        #expect(EventIdentity.key(for: timed, calendar: bangkok) == EventIdentity.key(for: timed, calendar: newYork))
        #expect(EventIdentity.key(for: timed, calendar: bangkok).rawValue == "ext:x|1800000000")
    }
}

@Suite("EventReconciler")
struct EventReconcilerTests {
    @Test func twoIndistinguishableEventsKeepTheirOwnRecords() {
        // Two "Standup"s at the same time in one calendar and no external identifier: neither may be dropped.
        let first = snapshot(eventIdentifier: "a", external: nil, title: "Standup")
        let second = snapshot(eventIdentifier: "b", external: nil, title: "Standup")

        let plan = EventReconciler.reconcile(snapshots: [first, second], stored: [], window: window)

        #expect(plan.inserts.count == 2)
        #expect(Set(plan.inserts.map(\.key)).count == 2)

        // And a second sync matches both to the same records instead of creating more.
        let stored = plan.inserts.map { insert in
            StoredEventRecord(
                key: insert.key,
                lastEventIdentifier: insert.snapshot.eventIdentifier,
                fingerprint: EventIdentity.fingerprint(for: insert.snapshot),
                isRecurring: false,
                startDate: insert.snapshot.startDate,
                endDate: insert.snapshot.endDate,
                state: .active
            )
        }
        let again = EventReconciler.reconcile(snapshots: [second, first], stored: stored, window: window)
        #expect(again.inserts.isEmpty)
        #expect(again.markMissing.isEmpty)
        #expect(again.updates.count == 2)
    }

    @Test func unchangedEventMatchesByExactKey() {
        let event = snapshot()
        let plan = EventReconciler.reconcile(snapshots: [event], stored: [record(from: event)], window: window)

        #expect(plan.inserts.isEmpty)
        #expect(plan.markMissing.isEmpty)
        #expect(plan.updates.count == 1)
        #expect(plan.updates.first?.reason == .exactKey)
        #expect(plan.updates.first?.isRekey == false)
    }

    @Test func newEventIsInserted() {
        let plan = EventReconciler.reconcile(snapshots: [snapshot()], stored: [], window: window)
        #expect(plan.inserts.count == 1)
        #expect(plan.updates.isEmpty)
    }

    @Test func movedRecurringOccurrenceKeepsItsIdentity() {
        let original = snapshot(external: "series", occurrence: base, recurring: true)
        let stored = record(from: original)
        // Same occurrence, moved two hours later: startDate changes, occurrenceDate does not.
        let moved = snapshot(external: "series", start: base + 2 * hour, occurrence: base, recurring: true)

        let plan = EventReconciler.reconcile(snapshots: [moved], stored: [stored], window: window)

        #expect(plan.inserts.isEmpty)
        #expect(plan.markMissing.isEmpty)
        #expect(plan.updates.first?.reason == .exactKey)
        #expect(plan.updates.first?.existingKey == stored.key)
    }

    @Test func occurrencesOfOneSeriesAreDistinctEvenWithSharedEventIdentifier() {
        let first = snapshot(eventIdentifier: "series-evt", external: "series", start: base, recurring: true)
        let secondDate = base + 7 * day
        let second = snapshot(eventIdentifier: "series-evt", external: "series", start: secondDate, recurring: true)

        let plan = EventReconciler.reconcile(snapshots: [first, second], stored: [record(from: first)], window: window)

        #expect(plan.updates.count == 1)
        #expect(plan.inserts.count == 1)
        #expect(plan.inserts.first?.snapshot.startDate == secondDate)
    }

    @Test func recurringOccurrenceIsNeverMatchedByEventIdentifier() {
        // The stored occurrence was removed and a different occurrence of the same series appeared.
        let removed = snapshot(eventIdentifier: "series-evt", external: "series", start: base, recurring: true)
        let other = snapshot(eventIdentifier: "series-evt", external: "series", start: base + 7 * day, recurring: true)

        let plan = EventReconciler.reconcile(snapshots: [other], stored: [record(from: removed)], window: window)

        #expect(plan.updates.isEmpty)
        #expect(plan.inserts.count == 1)
        #expect(plan.markMissing == [record(from: removed).key])
    }

    @Test func retitledEventWithoutExternalIDIsRelinkedByEventIdentifier() {
        let before = snapshot(eventIdentifier: "evt-9", external: nil, title: "Audit prep")
        let after = snapshot(eventIdentifier: "evt-9", external: nil, title: "Audit preparation")

        let plan = EventReconciler.reconcile(snapshots: [after], stored: [record(from: before)], window: window)

        #expect(plan.inserts.isEmpty)
        #expect(plan.markMissing.isEmpty)
        #expect(plan.updates.first?.reason == .eventIdentifier)
        #expect(plan.updates.first?.isRekey == true)
    }

    @Test func externalIDAppearingLaterIsRelinkedByFingerprint() {
        let before = snapshot(eventIdentifier: "old-id", external: nil)
        let after = snapshot(eventIdentifier: "new-id", external: "ext-now-available")

        let plan = EventReconciler.reconcile(snapshots: [after], stored: [record(from: before)], window: window)

        #expect(plan.inserts.isEmpty)
        #expect(plan.updates.first?.reason == .fingerprint)
        #expect(plan.updates.first?.newKey == EventIdentity.key(for: after))
    }

    @Test func ambiguousFingerprintDoesNotGuess() {
        let a = snapshot(eventIdentifier: "a", external: nil, title: "Standup")
        let b = snapshot(eventIdentifier: "b", external: nil, calendar: "cal-1", title: "Standup")
        // Two stored records share a fingerprint, so a new snapshot with that fingerprint is ambiguous.
        let storedA = record(from: a)
        let storedB = StoredEventRecord(
            key: EventKey(rawValue: "fp:other-key"),
            lastEventIdentifier: b.eventIdentifier,
            fingerprint: storedA.fingerprint,
            isRecurring: false,
            startDate: b.startDate,
            endDate: b.endDate,
            state: .active
        )
        let incoming = snapshot(eventIdentifier: "c", external: "ext-c", title: "Standup")

        let plan = EventReconciler.reconcile(snapshots: [incoming], stored: [storedA, storedB], window: window)

        #expect(plan.updates.isEmpty)
        #expect(plan.inserts.count == 1)
    }

    @Test func absentEventInsideWindowBecomesMissing() {
        let event = snapshot()
        let plan = EventReconciler.reconcile(snapshots: [], stored: [record(from: event)], window: window)
        #expect(plan.markMissing == [record(from: event).key])
    }

    @Test func eventOutsideWindowIsLeftAlone() {
        let old = snapshot(start: base - 200 * day)
        let plan = EventReconciler.reconcile(snapshots: [], stored: [record(from: old)], window: window)
        #expect(plan.markMissing.isEmpty)
    }

    @Test func alreadyMissingEventIsNotMarkedAgain() {
        let event = snapshot()
        let plan = EventReconciler.reconcile(snapshots: [], stored: [record(from: event, state: .missing)], window: window)
        #expect(plan.markMissing.isEmpty)
    }

    @Test func missingEventIsRestoredWhenItReappears() {
        let event = snapshot()
        let plan = EventReconciler.reconcile(
            snapshots: [event],
            stored: [record(from: event, state: .missing)],
            window: window
        )
        #expect(plan.updates.first?.wasMissing == true)
        #expect(plan.inserts.isEmpty)
    }

    @Test func sameExternalIDInTwoCalendarsProducesTwoDistinctKeys() {
        let a = snapshot(eventIdentifier: "a", external: "shared", calendar: "cal-a")
        let b = snapshot(eventIdentifier: "b", external: "shared", calendar: "cal-b")

        let plan = EventReconciler.reconcile(snapshots: [a, b], stored: [], window: window)

        #expect(plan.inserts.count == 2)
        #expect(Set(plan.inserts.map(\.key)).count == 2)
    }

    @Test func resultDoesNotDependOnInputOrder() {
        let a = snapshot(eventIdentifier: "a", external: "shared", calendar: "cal-a")
        let b = snapshot(eventIdentifier: "b", external: "shared", calendar: "cal-b")

        let forward = EventReconciler.reconcile(snapshots: [a, b], stored: [], window: window)
        let reversed = EventReconciler.reconcile(snapshots: [b, a], stored: [], window: window)

        #expect(forward == reversed)
    }
}

@Suite("EventIdentity")
struct EventIdentityTests {
    @Test func keyIgnoresEventIdentifier() {
        let a = snapshot(eventIdentifier: "one")
        let b = snapshot(eventIdentifier: "two")
        #expect(EventIdentity.key(for: a) == EventIdentity.key(for: b))
    }

    @Test func keyChangesWithOccurrenceDate() {
        let a = snapshot(external: "series", occurrence: base, recurring: true)
        let b = snapshot(external: "series", occurrence: base + 7 * day, recurring: true)
        #expect(EventIdentity.key(for: a) != EventIdentity.key(for: b))
    }

    @Test func blankExternalIDFallsBackToFingerprintKey() {
        let key = EventIdentity.key(for: snapshot(external: "   "))
        #expect(key.rawValue.hasPrefix("fp:"))
    }
}
