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
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600

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

private func item(_ kind: ContextItemKind, done: Bool = false) -> ContextItemValue {
    ContextItemValue(id: UUID(), kind: kind, title: "x", detail: nil, url: nil, isDone: done, createdAt: now)
}

@Suite("TodayTimeline")
struct TodayTimelineTests {
    @Test func inProgressEventBecomesTheNowHero() {
        let running = event("Audit", from: now - 20 * minute)
        let later = event("Review", from: now + 2 * hour)

        let snapshot = TodayTimeline.build(events: [later, running], now: now, calendar: calendar)

        #expect(snapshot.hero?.kind == .now)
        #expect(snapshot.hero?.entry.event.title == "Audit")
        let progress = snapshot.hero?.progress ?? -1
        #expect(abs(progress - 1.0 / 3.0) < 0.001)
    }

    @Test func nextEventTodayIsUpNextWhenNothingIsRunning() {
        let done = event("Standup", from: now - 3 * hour)
        let soon = event("Vendor call", from: now + 30 * minute)
        let later = event("Review", from: now + 3 * hour)

        let snapshot = TodayTimeline.build(events: [later, done, soon], now: now, calendar: calendar)

        #expect(snapshot.hero?.kind == .upNext)
        #expect(snapshot.hero?.entry.event.title == "Vendor call")
        #expect(snapshot.hero?.progress == nil)
    }

    @Test func firstEventTomorrowIsHeroWhenTodayIsOver() {
        let done = event("Standup", from: now - 3 * hour)
        let tomorrow = event("Board prep", from: now + 24 * hour)

        let snapshot = TodayTimeline.build(events: [done, tomorrow], now: now, calendar: calendar)

        #expect(snapshot.hero?.kind == .tomorrow)
        #expect(snapshot.timeline.map(\.event.title) == ["Standup"])
    }

    @Test func eventsMoreThanADayAheadAreNotHero() {
        let far = event("Offsite", from: now + 72 * hour)
        let snapshot = TodayTimeline.build(events: [far], now: now, calendar: calendar)
        #expect(snapshot.hero == nil)
        #expect(snapshot.isEmpty)
    }

    @Test func phasesFollowTheClock() {
        let past = event("A", from: now - 3 * hour)
        let current = event("B", from: now - 10 * minute)
        let upcoming = event("C", from: now + hour)

        let snapshot = TodayTimeline.build(events: [upcoming, past, current], now: now, calendar: calendar)

        #expect(snapshot.timeline.map(\.phase) == [.past, .current, .upcoming])
        #expect(snapshot.stats.total == 3)
        #expect(snapshot.stats.completed == 1)
        #expect(snapshot.stats.remaining == 2)
    }

    @Test func allDayEventsAreSeparateAndNeverHero() {
        let holiday = event("Audit week", from: calendar.startOfDay(for: now), lasting: 24 * hour, allDay: true)
        let snapshot = TodayTimeline.build(events: [holiday], now: now, calendar: calendar)

        #expect(snapshot.allDay.map(\.event.title) == ["Audit week"])
        #expect(snapshot.timeline.isEmpty)
        #expect(snapshot.hero == nil)
    }

    @Test func missingEventsAreExcludedButCounted() {
        let gone = event("Cancelled", from: now + hour, state: .missing)
        let kept = event("Real", from: now + 2 * hour)

        let snapshot = TodayTimeline.build(events: [gone, kept], now: now, calendar: calendar)

        #expect(snapshot.timeline.map(\.event.title) == ["Real"])
        #expect(snapshot.hero?.entry.event.title == "Real")
        #expect(snapshot.stats.missing == 1)
    }

    @Test func overlappingEventsPickTheLatestStartedAsNow() {
        let long = event("Workshop", from: now - 2 * hour, lasting: 4 * hour)
        let short = event("Call", from: now - 5 * minute, lasting: 30 * minute)

        let snapshot = TodayTimeline.build(events: [long, short], now: now, calendar: calendar)

        #expect(snapshot.hero?.entry.event.title == "Call")
    }

    @Test func openTasksIgnoreEventsThatAreAlreadyOver() {
        let done = event("Done", from: now - 3 * hour, items: [item(.task), item(.task)])
        let running = event("Running", from: now - 10 * minute, items: [item(.task), item(.task, done: true)])
        let later = event("Later", from: now + hour, items: [item(.task), item(.note)])

        let snapshot = TodayTimeline.build(events: [done, running, later], now: now, calendar: calendar)

        #expect(snapshot.openTasks == 2)
    }

    @Test func progressIsClampedAndSafeForZeroDuration() {
        let instant = event("Ping", from: now, lasting: 0)
        let running = event("Run", from: now - hour, lasting: 4 * hour)
        #expect(TodayTimeline.progress(of: instant, at: now) == 0)
        #expect(TodayTimeline.progress(of: running, at: now - 2 * hour) == 0)
        #expect(TodayTimeline.progress(of: running, at: now + 10 * hour) == 1)
    }

    @Test func buildIsIndependentOfInputOrder() {
        let a = event("A", from: now + hour)
        let b = event("B", from: now + 2 * hour)
        let c = event("C", from: now - 3 * hour)
        let forward = TodayTimeline.build(events: [a, b, c], now: now, calendar: calendar)
        let shuffled = TodayTimeline.build(events: [c, b, a], now: now, calendar: calendar)
        #expect(forward == shuffled)
    }
}

@Suite("ContextSummary")
struct ContextSummaryTests {
    @Test func countsEachKindAndOpenTasks() {
        let summary = ContextSummary(items: [
            item(.note), item(.link), item(.task), item(.task, done: true), item(.file), item(.voice)
        ])
        #expect(summary.notes == 1)
        #expect(summary.links == 1)
        #expect(summary.tasks == 2)
        #expect(summary.openTasks == 1)
        #expect(summary.attachments == 2)
        #expect(summary.total == 6)
        #expect(!summary.isEmpty)
    }

    @Test func emptyItemsGiveEmptySummary() {
        #expect(ContextSummary(items: []).isEmpty)
    }
}

@Suite("ContextItemDraft")
struct ContextItemDraftTests {
    @Test func noteRequiresATitle() {
        #expect(throws: ContextValidationError.emptyTitle) {
            try ContextItemDraft(kind: .note, title: "   ").validated()
        }
    }

    @Test func titleIsTrimmedAndEmptyDetailBecomesNil() throws {
        let valid = try ContextItemDraft(kind: .task, title: "  Send agenda  ", detail: "  ").validated()
        #expect(valid.title == "Send agenda")
        #expect(valid.detail == nil)
    }

    @Test func overlongTitleIsRejected() {
        let long = String(repeating: "a", count: ContextItemDraft.maxTitleLength + 1)
        #expect(throws: ContextValidationError.titleTooLong) {
            try ContextItemDraft(kind: .note, title: long).validated()
        }
    }

    @Test func linkWithoutSchemeGetsHTTPSAndHostAsTitle() throws {
        let valid = try ContextItemDraft(kind: .link, urlString: "example.com/audit-plan").validated()
        #expect(valid.url?.absoluteString == "https://example.com/audit-plan")
        #expect(valid.title == "example.com")
    }

    @Test func linkKeepsCustomTitle() throws {
        let valid = try ContextItemDraft(kind: .link, title: "Audit Plan", urlString: "https://example.com").validated()
        #expect(valid.title == "Audit Plan")
    }

    @Test(arguments: ["", "   ", "ftp://example.com", "not a url"])
    func invalidLinksAreRejected(input: String) {
        #expect(throws: ContextValidationError.invalidURL) {
            try ContextItemDraft(kind: .link, urlString: input).validated()
        }
    }

    @Test func voiceItemsAreNotCreatableYet() {
        #expect(throws: ContextValidationError.unsupportedKind) {
            try ContextItemDraft(kind: .voice, title: "x").validated()
        }
    }

    @Test func fileItemRequiresAStoredFile() {
        #expect(throws: ContextValidationError.missingFile) {
            try ContextItemDraft(kind: .file, title: "Budget").validated()
        }
    }

    @Test func fileItemDefaultsItsTitleToTheFileName() throws {
        let valid = try ContextItemDraft(kind: .file, fileName: "abc/Budget.xlsx").validated()
        #expect(valid.title == "Budget.xlsx")
        #expect(valid.fileName == "abc/Budget.xlsx")
    }
}
