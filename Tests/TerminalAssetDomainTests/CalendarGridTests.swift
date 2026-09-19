import Foundation
import Testing
@testable import TerminalAssetDomain

private func makeCalendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? Date(timeIntervalSince1970: 0)
}

private func event(
    _ title: String,
    _ start: Date,
    minutes: Double = 60,
    allDay: Bool = false,
    state: SyncState = .active
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"), title: title, startDate: start,
        endDate: start.addingTimeInterval(minutes * 60), isAllDay: allDay, location: nil,
        syncState: state, items: []
    )
}

@Suite("MonthGrid")
struct MonthGridTests {
    @Test func septemberTwentySixStartsOnATuesday() {
        let sunday = makeCalendar(firstWeekday: 1)
        let weeks = MonthGrid.weeks(containing: date(2026, 9, 15, calendar: sunday), calendar: sunday, today: date(2026, 9, 20, calendar: sunday))

        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        // Sunday-first: the grid starts on Sunday 30 August.
        #expect(weeks[0][0].date == date(2026, 8, 30, calendar: sunday))
        #expect(weeks[0][0].isInDisplayedMonth == false)
        #expect(weeks[0][2].date == date(2026, 9, 1, calendar: sunday))
        #expect(weeks[0][2].isInDisplayedMonth)
    }

    @Test func mondayFirstShiftsTheGrid() {
        let monday = makeCalendar(firstWeekday: 2)
        let weeks = MonthGrid.weeks(containing: date(2026, 9, 15, calendar: monday), calendar: monday, today: date(2026, 9, 20, calendar: monday))
        #expect(weeks[0][0].date == date(2026, 8, 31, calendar: monday))
        #expect(weeks[0][1].date == date(2026, 9, 1, calendar: monday))
    }

    @Test func todayIsMarkedExactlyOnce() {
        let calendar = makeCalendar(firstWeekday: 1)
        let today = date(2026, 9, 20, 14, 30, calendar: calendar)
        let days = MonthGrid.weeks(containing: today, calendar: calendar, today: today).flatMap { $0 }
        #expect(days.filter(\.isToday).count == 1)
        #expect(days.first(where: \.isToday)?.date == date(2026, 9, 20, calendar: calendar))
    }

    @Test func aFourWeekFebruaryAndASixWeekAugust() {
        let calendar = makeCalendar(firstWeekday: 1)
        #expect(MonthGrid.weeks(containing: date(2026, 2, 10, calendar: calendar), calendar: calendar, today: date(2026, 2, 10, calendar: calendar)).count == 4)
        #expect(MonthGrid.weeks(containing: date(2026, 8, 10, calendar: calendar), calendar: calendar, today: date(2026, 8, 10, calendar: calendar)).count == 6)
    }

    @Test func leapDayExists() {
        let calendar = makeCalendar(firstWeekday: 1)
        let days = MonthGrid.weeks(containing: date(2028, 2, 1, calendar: calendar), calendar: calendar, today: date(2028, 2, 1, calendar: calendar)).flatMap { $0 }
        #expect(days.contains { $0.isInDisplayedMonth && $0.date == date(2028, 2, 29, calendar: calendar) })
    }

    @Test func everyGridStartsOnTheFirstWeekday() {
        for firstWeekday in 1...7 {
            let calendar = makeCalendar(firstWeekday: firstWeekday)
            let weeks = MonthGrid.weeks(containing: date(2026, 9, 15, calendar: calendar), calendar: calendar, today: date(2026, 9, 15, calendar: calendar))
            #expect(calendar.component(.weekday, from: weeks[0][0].date) == firstWeekday)
        }
    }

    @Test func weekdayHeadersStartFromTheFirstWeekday() {
        let monday = makeCalendar(firstWeekday: 2)
        let headers = MonthGrid.weekdayHeaders(calendar: monday)
        #expect(headers.count == 7)
        #expect(headers[0] == monday.veryShortStandaloneWeekdaySymbols[1])
    }

    @Test func monthNavigationCrossesYears() {
        let calendar = makeCalendar(firstWeekday: 1)
        let december = date(2026, 12, 15, calendar: calendar)
        #expect(MonthGrid.month(byAdding: 1, to: december, calendar: calendar) == date(2027, 1, 1, calendar: calendar))
        #expect(MonthGrid.month(byAdding: -12, to: december, calendar: calendar) == date(2025, 12, 1, calendar: calendar))
    }
}

@Suite("CalendarEvents")
struct CalendarEventsTests {
    private let calendar = makeCalendar(firstWeekday: 1)

    @Test func multiDayEventsCountOnEveryDay() {
        let trip = event("Trip", date(2026, 9, 20, 22, calendar: calendar), minutes: 60 * 30)  // until 21st 04:00... 22:00 + 30h = 22nd 04:00
        let counts = CalendarEvents.counts(for: [trip], calendar: calendar)
        #expect(counts[date(2026, 9, 20, calendar: calendar)] == 1)
        #expect(counts[date(2026, 9, 21, calendar: calendar)] == 1)
        #expect(counts[date(2026, 9, 22, calendar: calendar)] == 1)
        #expect(counts[date(2026, 9, 23, calendar: calendar)] == nil)
    }

    @Test func anEventEndingAtMidnightDoesNotSpillIntoTheNextDay() {
        let late = event("Late", date(2026, 9, 20, 23, calendar: calendar), minutes: 60)
        let counts = CalendarEvents.counts(for: [late], calendar: calendar)
        #expect(counts[date(2026, 9, 21, calendar: calendar)] == nil)
    }

    @Test func missingEventsAreNotCounted() {
        let gone = event("Gone", date(2026, 9, 20, 9, calendar: calendar), state: .missing)
        #expect(CalendarEvents.counts(for: [gone], calendar: calendar).isEmpty)
    }

    @Test func agendaPutsAllDayFirstThenSortsByTime() {
        let day = date(2026, 9, 20, calendar: calendar)
        let events = [
            event("Later", date(2026, 9, 20, 15, calendar: calendar)),
            event("Holiday", day, minutes: 24 * 60, allDay: true),
            event("Earlier", date(2026, 9, 20, 9, calendar: calendar)),
            event("Other day", date(2026, 9, 21, 9, calendar: calendar))
        ]
        let agenda = CalendarEvents.events(on: day, in: events, calendar: calendar)
        #expect(agenda.map(\.title) == ["Holiday", "Earlier", "Later"])
    }
}

@Suite("DayLayout")
struct DayLayoutTests {
    private let calendar = makeCalendar(firstWeekday: 1)
    private var day: Date { date(2026, 9, 20, calendar: calendar) }

    @Test func separateEventsUseTheFullWidth() {
        let events = [
            event("A", date(2026, 9, 20, 9, calendar: calendar)),
            event("B", date(2026, 9, 20, 11, calendar: calendar))
        ]
        let layout = DayLayout.layout(events: events, on: day, calendar: calendar)
        #expect(layout.allSatisfy { $0.columnCount == 1 && $0.column == 0 })
    }

    @Test func overlappingEventsSitSideBySide() {
        let events = [
            event("A", date(2026, 9, 20, 9, calendar: calendar), minutes: 90),
            event("B", date(2026, 9, 20, 10, calendar: calendar), minutes: 60)
        ]
        let layout = DayLayout.layout(events: events, on: day, calendar: calendar)
        #expect(layout.count == 2)
        #expect(layout.allSatisfy { $0.columnCount == 2 })
        #expect(Set(layout.map(\.column)) == [0, 1])
    }

    @Test func aFreedColumnIsReused() {
        let events = [
            event("Long", date(2026, 9, 20, 9, calendar: calendar), minutes: 180),
            event("Short", date(2026, 9, 20, 9, calendar: calendar), minutes: 60),
            event("After short", date(2026, 9, 20, 10, calendar: calendar), minutes: 60)
        ]
        let layout = DayLayout.layout(events: events, on: day, calendar: calendar)
        let byTitle = Dictionary(uniqueKeysWithValues: layout.map { ($0.event.title, $0) })
        #expect(byTitle["Long"]?.column == 0)
        #expect(byTitle["Short"]?.column == 1)
        #expect(byTitle["After short"]?.column == 1)
        #expect(layout.allSatisfy { $0.columnCount == 2 })
    }

    @Test func clustersAreIndependent() {
        let events = [
            event("Morning A", date(2026, 9, 20, 9, calendar: calendar), minutes: 90),
            event("Morning B", date(2026, 9, 20, 9, 30, calendar: calendar), minutes: 60),
            event("Afternoon", date(2026, 9, 20, 15, calendar: calendar))
        ]
        let layout = DayLayout.layout(events: events, on: day, calendar: calendar)
        let afternoon = layout.first { $0.event.title == "Afternoon" }
        #expect(afternoon?.columnCount == 1)
    }

    @Test func shortEventsGetAMinimumHeightAndAllDayIsExcluded() {
        let events = [
            event("Ping", date(2026, 9, 20, 9, calendar: calendar), minutes: 5),
            event("Holiday", day, minutes: 24 * 60, allDay: true)
        ]
        let layout = DayLayout.layout(events: events, on: day, calendar: calendar, minimumMinutes: 30)
        #expect(layout.count == 1)
        #expect(layout.first.map { $0.endMinute - $0.startMinute } == 30)
    }

    @Test func eventsSpanningMidnightAreClippedToTheDay() {
        let overnight = event("Overnight", date(2026, 9, 19, 22, calendar: calendar), minutes: 5 * 60)
        let layout = DayLayout.layout(events: [overnight], on: day, calendar: calendar)
        #expect(layout.first?.startMinute == 0)
        #expect(layout.first?.endMinute == 180)
    }
}
