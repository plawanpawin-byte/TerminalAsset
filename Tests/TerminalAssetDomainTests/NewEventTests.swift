import Foundation
import Testing
@testable import TerminalAssetDomain

private let utc = TimeZone(identifier: "UTC") ?? .gmt
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}()

/// 2027-01-15 10:20 UTC.
private let now = Date(timeIntervalSince1970: 1_800_008_400)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func draft(
    _ title: String = "Lunch",
    start: Date = now,
    lasting duration: TimeInterval = hour,
    allDay: Bool = false,
    location: String = ""
) -> NewEventDraft {
    NewEventDraft(title: title, start: start, end: start + duration, isAllDay: allDay, location: location)
}

@Suite("NewEventDraft")
struct NewEventDraftTests {
    // MARK: Validation

    @Test func trimsTitleAndLocation() throws {
        let event = try draft("  Lunch  ", location: "  Cafe  ").validated(calendar: calendar)
        #expect(event.title == "Lunch")
        #expect(event.location == "Cafe")
    }

    @Test func blankLocationBecomesNil() throws {
        let event = try draft(location: "   ").validated(calendar: calendar)
        #expect(event.location == nil)
    }

    @Test func emptyTitleIsRejected() {
        #expect(throws: EventDraftError.emptyTitle) {
            try draft("   ").validated(calendar: calendar)
        }
    }

    @Test func overlongTitleIsRejected() {
        let long = String(repeating: "a", count: NewEventDraft.maxTitleLength + 1)
        #expect(throws: EventDraftError.titleTooLong) {
            try draft(long).validated(calendar: calendar)
        }
    }

    @Test func overlongLocationIsRejected() {
        let long = String(repeating: "a", count: NewEventDraft.maxLocationLength + 1)
        #expect(throws: EventDraftError.locationTooLong) {
            try draft(location: long).validated(calendar: calendar)
        }
    }

    @Test func timedEventMustEndAfterItStarts() {
        #expect(throws: EventDraftError.endNotAfterStart) {
            try draft(lasting: 0).validated(calendar: calendar)
        }
        #expect(throws: EventDraftError.endNotAfterStart) {
            try draft(lasting: -hour).validated(calendar: calendar)
        }
    }

    @Test func allDayEventsSnapToWholeDays() throws {
        let event = try draft(allDay: true).validated(calendar: calendar)
        #expect(event.isAllDay)
        #expect(event.start == calendar.startOfDay(for: now))
        #expect(event.end == calendar.startOfDay(for: now))
    }

    @Test func allDayEventMayEndOnALaterDay() throws {
        let event = try draft(lasting: 2 * day, allDay: true).validated(calendar: calendar)
        #expect(event.end == calendar.startOfDay(for: now) + 2 * day)
    }

    @Test func allDayEventCannotEndBeforeItStarts() {
        #expect(throws: EventDraftError.endNotAfterStart) {
            try draft(lasting: -2 * day, allDay: true).validated(calendar: calendar)
        }
    }

    @Test func repeatDefaultsToNeverAndIsKept() throws {
        #expect(try draft().validated(calendar: calendar).repeatRule == .never)
        var input = draft()
        input.repeatRule = .biweekly
        #expect(try input.validated(calendar: calendar).repeatRule == .biweekly)
    }

    @Test func calendarChoiceIsKept() throws {
        var input = draft()
        input.calendarID = "work"
        #expect(try input.validated(calendar: calendar).calendarID == "work")
    }

    // MARK: Moving the start

    @Test func movingTheStartKeepsTheDuration() {
        var input = draft(lasting: 90 * 60)
        input.moveStart(to: now + 3 * hour)
        #expect(input.start == now + 3 * hour)
        #expect(input.end == now + 3 * hour + 90 * 60)
    }

    @Test func movingTheStartOfAnInvertedDraftRepairsIt() {
        var input = draft(lasting: -hour)
        input.moveStart(to: now + hour)
        #expect(input.end == input.start)
    }

    // MARK: Defaults

    @Test func todayStartsAtTheNextFullHour() {
        let input = NewEventDraft.starting(on: now, now: now, calendar: calendar)
        // 10:20 → 11:00, one hour long.
        #expect(input.start == calendar.date(bySettingHour: 11, minute: 0, second: 0, of: now))
        #expect(input.end == input.start + hour)
    }

    @Test func lateEveningStaysOnTheSameDay() {
        let late = calendar.date(bySettingHour: 23, minute: 40, second: 0, of: now) ?? now
        let input = NewEventDraft.starting(on: late, now: late, calendar: calendar)
        #expect(input.start == calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        #expect(calendar.isDate(input.start, inSameDayAs: late))
    }

    @Test func otherDaysStartAtNine() {
        let tomorrow = now + day
        let input = NewEventDraft.starting(on: tomorrow, now: now, calendar: calendar)
        #expect(input.start == calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow))
        #expect(input.end == input.start + hour)
    }

    @Test func defaultDraftIsNotYetValidBecauseTheTitleIsEmpty() {
        let input = NewEventDraft.starting(on: now, now: now, calendar: calendar)
        #expect(throws: EventDraftError.emptyTitle) {
            try input.validated(calendar: calendar)
        }
    }
}

private func validEvent(
    _ title: String = "Lunch",
    calendarID: String? = nil
) throws -> ValidatedNewEvent {
    var input = draft(title)
    input.calendarID = calendarID
    return try input.validated(calendar: calendar)
}

@Suite("StubCalendarRepository writing")
struct StubCalendarWritingTests {
    private let window = DateInterval(start: now - day, end: now + 2 * day)

    @Test func createdEventShowsUpInTheCalendar() async throws {
        let repository = StubCalendarRepository(snapshots: [])

        let created = try await repository.createEvent(try validEvent("Lunch"))
        let found = try await repository.events(in: window)

        #expect(found == [created])
        #expect(created.title == "Lunch")
        #expect(created.occurrenceDate == created.startDate)
        #expect(created.isRecurring == false)
    }

    @Test func createdEventGetsAStableKey() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        let created = try await repository.createEvent(try validEvent())
        #expect(EventIdentity.key(for: created).rawValue.hasPrefix("ext:"))
    }

    @Test func twoCreatedEventsAreDistinct() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        let first = try await repository.createEvent(try validEvent("Same"))
        let second = try await repository.createEvent(try validEvent("Same"))
        #expect(EventIdentity.key(for: first) != EventIdentity.key(for: second))
    }

    @Test func usesTheDefaultCalendarWhenNoneIsChosen() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        let created = try await repository.createEvent(try validEvent())
        #expect(created.calendarID == "stub.personal")
    }

    @Test func usesTheChosenCalendar() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        let created = try await repository.createEvent(try validEvent(calendarID: "stub.work"))
        #expect(created.calendarID == "stub.work")
    }

    @Test func aRepeatingEventIsMarkedRecurring() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        var input = draft("Standup")
        input.repeatRule = .weekly
        let created = try await repository.createEvent(try input.validated(calendar: calendar))
        #expect(created.isRecurring)
        #expect(try await repository.createEvent(try validEvent()).isRecurring == false)
    }

    @Test func unknownCalendarIsRejected() async {
        let repository = StubCalendarRepository(snapshots: [])
        await #expect(throws: CalendarError.calendarNotFound) {
            try await repository.createEvent(try validEvent(calendarID: "gone"))
        }
    }

    @Test func noWritableCalendarIsReported() async {
        let repository = StubCalendarRepository(snapshots: [], calendars: [])
        await #expect(throws: CalendarError.noWritableCalendar) {
            try await repository.createEvent(try validEvent())
        }
    }

    @Test func writingWithoutPermissionFails() async {
        let repository = StubCalendarRepository(snapshots: [], authorization: .denied)
        await #expect(throws: CalendarError.permissionDenied) {
            try await repository.createEvent(try validEvent())
        }
        await #expect(throws: CalendarError.permissionDenied) {
            try await repository.writableCalendars()
        }
    }

    @Test func writeOnlyAccessCanCreateButNotRead() async throws {
        let repository = StubCalendarRepository(snapshots: [], authorization: .writeOnly)
        _ = try await repository.createEvent(try validEvent())
        await #expect(throws: CalendarError.permissionDenied) {
            try await repository.events(in: window)
        }
    }

    @Test func listsTheWritableCalendars() async throws {
        let repository = StubCalendarRepository(snapshots: [])
        let calendars = try await repository.writableCalendars()
        #expect(calendars.map(\.title) == ["Personal", "Work"])
        #expect(calendars.filter(\.isDefault).count == 1)
    }
}
