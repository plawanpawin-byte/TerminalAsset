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

private func event(
    _ title: String,
    from start: Date,
    lasting duration: TimeInterval = hour,
    allDay: Bool = false,
    state: SyncState = .active
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"),
        title: title,
        startDate: start,
        endDate: start + duration,
        isAllDay: allDay,
        location: nil,
        syncState: state,
        items: []
    )
}

@Suite("CalendarHistory")
struct CalendarHistoryTests {
    @Test func groupsEventsByDayNewestFirst() {
        let today = event("Today", from: now)
        let yesterday = event("Yesterday", from: now - day)
        let tomorrow = event("Tomorrow", from: now + day)

        let days = CalendarHistory.days(from: [yesterday, today, tomorrow], calendar: calendar)

        #expect(days.map(\.events.first?.title) == ["Tomorrow", "Today", "Yesterday"])
    }

    @Test func eventsOnTheSameDayAreOneSection() {
        let morning = event("Morning", from: now - 3 * hour)
        let noon = event("Noon", from: now)

        let days = CalendarHistory.days(from: [noon, morning], calendar: calendar)

        #expect(days.count == 1)
        #expect(days[0].events.map(\.title) == ["Morning", "Noon"])
    }

    @Test func allDayEventsSortBeforeTimedOnesOnTheSameDay() {
        let timed = event("Timed", from: now)
        let allDay = event("Holiday", from: calendar.startOfDay(for: now), allDay: true)

        let days = CalendarHistory.days(from: [timed, allDay], calendar: calendar)

        #expect(days[0].events.map(\.title) == ["Holiday", "Timed"])
    }

    @Test func missingEventsAreExcluded() {
        let kept = event("Kept", from: now)
        let gone = event("Gone", from: now - day, state: .missing)

        let days = CalendarHistory.days(from: [kept, gone], calendar: calendar)

        #expect(days.count == 1)
        #expect(days[0].events.map(\.title) == ["Kept"])
    }

    @Test func theDayIsTheStartOfDay() {
        let days = CalendarHistory.days(from: [event("Late", from: now)], calendar: calendar)
        #expect(days[0].day == calendar.startOfDay(for: now))
    }

    @Test func noEventsGivesNoDays() {
        #expect(CalendarHistory.days(from: [], calendar: calendar).isEmpty)
    }
}
