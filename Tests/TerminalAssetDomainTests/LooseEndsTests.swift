import Foundation
import Testing
@testable import TerminalAssetDomain

private let utc = TimeZone(identifier: "UTC") ?? .gmt
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}()

/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func task(done: Bool) -> ContextItemValue {
    ContextItemValue(id: UUID(), kind: .task, title: "t", detail: nil, url: nil, isDone: done, createdAt: now)
}

private func event(
    _ title: String,
    from offset: TimeInterval,
    lasting duration: TimeInterval = hour,
    state: SyncState = .active,
    items: [ContextItemValue] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"), title: title,
        startDate: now + offset, endDate: now + offset + duration,
        isAllDay: false, location: nil, syncState: state, items: items
    )
}

@Suite("LooseEnds")
struct LooseEndsTests {
    @Test func eventsFromEarlierDaysWithOpenTasksAreLooseEnds() {
        let result = LooseEnds.make(
            from: [
                event("Yesterday", from: -day, items: [task(done: false)]),
                event("Last week", from: -6 * day, items: [task(done: false), task(done: true)])
            ],
            now: now, calendar: calendar
        )
        #expect(result.map(\.title) == ["Yesterday", "Last week"])
    }

    @Test func todaysEventsAreNotLooseEnds() {
        // 07:00 today: already over, but it is on today's schedule, so listing it again would repeat it.
        let result = LooseEnds.make(
            from: [event("Earlier today", from: -3 * hour, items: [task(done: false)])],
            now: now, calendar: calendar
        )
        #expect(result.isEmpty)
    }

    @Test func aFinishedTaskListIsNotALooseEnd() {
        let result = LooseEnds.make(
            from: [event("Closed", from: -day, items: [task(done: true)])], now: now, calendar: calendar
        )
        #expect(result.isEmpty)
    }

    @Test func eventsWithoutTasksAreNotLooseEnds() {
        #expect(LooseEnds.make(from: [event("Plain", from: -day)], now: now, calendar: calendar).isEmpty)
    }

    @Test func upcomingEventsAreNotLooseEnds() {
        let result = LooseEnds.make(
            from: [event("Tomorrow", from: day, items: [task(done: false)])], now: now, calendar: calendar
        )
        #expect(result.isEmpty)
    }

    @Test func missingEventsAreIgnored() {
        let result = LooseEnds.make(
            from: [event("Gone", from: -day, state: .missing, items: [task(done: false)])],
            now: now, calendar: calendar
        )
        #expect(result.isEmpty)
    }

    @Test func theMostRecentlyEndedComesFirstAndTheListIsLimited() {
        let events = (1...8).map { event("E\($0)", from: -Double($0) * day, items: [task(done: false)]) }
        let result = LooseEnds.make(from: events, now: now, calendar: calendar, limit: 3)
        #expect(result.map(\.title) == ["E1", "E2", "E3"])
    }

    @Test func anEventThatEndedJustBeforeMidnightCounts() {
        // Ended 23:30 yesterday.
        let result = LooseEnds.make(
            from: [event("Late", from: -11 * hour, lasting: hour / 2, items: [task(done: false)])],
            now: now, calendar: calendar
        )
        #expect(result.map(\.title) == ["Late"])
    }
}
