import Foundation
import Testing
@testable import TerminalAssetDomain

/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func task(done: Bool) -> ContextItemValue {
    ContextItemValue(id: UUID(), kind: .task, title: "t", detail: nil, url: nil, isDone: done, createdAt: now)
}

private func event(
    _ title: String,
    from start: Date,
    lasting duration: TimeInterval = hour,
    allDay: Bool = false,
    state: SyncState = .active,
    items: [ContextItemValue] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"),
        title: title,
        startDate: start,
        endDate: start + duration,
        isAllDay: allDay,
        location: nil,
        syncState: state,
        items: items
    )
}

@Suite("AssistantBriefing")
struct AssistantBriefingTests {
    @Test func upNextIsTheSoonestEventThatHasNotEnded() {
        let soon = event("Soon", from: now + hour)
        let later = event("Later", from: now + 3 * hour)
        let past = event("Past", from: now - 2 * hour)

        let briefing = AssistantBriefing.make(from: [later, past, soon], now: now)

        #expect(briefing.upNext?.title == "Soon")
    }

    @Test func anOngoingEventIsPreferredOverALaterOne() {
        let ongoing = event("Ongoing", from: now - 15 * 60, lasting: hour) // started 15m ago, still running
        let upcoming = event("Upcoming", from: now + hour)

        let briefing = AssistantBriefing.make(from: [upcoming, ongoing], now: now)

        #expect(briefing.upNext?.title == "Ongoing")
    }

    @Test func allDayEventsAreNotUpNext() {
        let allDay = event("Holiday", from: now - 6 * hour, lasting: day, allDay: true)
        let timed = event("Meeting", from: now + hour)

        let briefing = AssistantBriefing.make(from: [allDay, timed], now: now)

        #expect(briefing.upNext?.title == "Meeting")
    }

    @Test func upNextIsNilWhenEverythingHasEnded() {
        let briefing = AssistantBriefing.make(from: [event("Done", from: now - 3 * hour)], now: now)
        #expect(briefing.upNext == nil)
    }

    @Test func looseEndsAreEndedEventsWithOpenTasksNewestFirst() {
        let yesterday = event("Yesterday", from: now - day, items: [task(done: false)])
        let earlier = event("Earlier", from: now - 3 * hour, items: [task(done: false), task(done: true)])
        let noOpen = event("Closed", from: now - 2 * hour, items: [task(done: true)])
        let future = event("Future", from: now + hour, items: [task(done: false)])

        let briefing = AssistantBriefing.make(from: [yesterday, earlier, noOpen, future], now: now)

        #expect(briefing.looseEnds.map(\.title) == ["Earlier", "Yesterday"])
    }

    @Test func looseEndsAreLimited() {
        let events = (1...8).map {
            event("E\($0)", from: now - Double($0) * hour, items: [task(done: false)])
        }
        let briefing = AssistantBriefing.make(from: events, now: now, maxLooseEnds: 3)
        #expect(briefing.looseEnds.count == 3)
    }

    @Test func missingEventsAreIgnored() {
        let gone = event("Gone", from: now + hour, state: .missing)
        let goneTask = event("GoneTask", from: now - hour, state: .missing, items: [task(done: false)])

        let briefing = AssistantBriefing.make(from: [gone, goneTask], now: now)

        #expect(briefing.upNext == nil)
        #expect(briefing.looseEnds.isEmpty)
    }
}
