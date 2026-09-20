#if canImport(UserNotifications)
import Foundation
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let start = Date(timeIntervalSince1970: 1_800_010_000)

private func task() -> ContextItemValue {
    ContextItemValue(
        id: UUID(), kind: .task, title: "t", detail: nil, url: nil, isDone: false,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

/// A reminder built the way the app builds it: through the planner, 15 minutes before an event.
private func reminder(title: String = "Audit", items: [ContextItemValue]) throws -> PrepReminder {
    let event = TimelineEvent(
        key: EventKey(rawValue: "k"), title: title,
        startDate: start, endDate: start.addingTimeInterval(3600),
        isAllDay: false, location: nil, syncState: .active, items: items
    )
    let plan = PrepReminderPlanner.plan(from: [event], now: start.addingTimeInterval(-3600))
    return try #require(plan.first)
}

@Suite("ReminderText")
struct ReminderTextTests {
    @Test func theTitleNamesTheEventAndHowSoonItStarts() throws {
        let text = ReminderText.title(for: try reminder(items: []))
        #expect(text.contains("Audit"))
        #expect(text.contains("15"))
    }

    @Test func aBareEventAsksForContext() throws {
        #expect(!ReminderText.body(for: try reminder(items: [])).isEmpty)
    }

    @Test func aPreparedEventListsWhatIsWaiting() throws {
        let note = ContextItemValue(
            id: UUID(), kind: .note, title: "n", detail: nil, url: nil, isDone: false,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let text = ReminderText.body(for: try reminder(items: [task(), task(), note]))
        #expect(text.contains("2"))
        #expect(text.contains("1"))
        #expect(text.contains("·"))
    }

    @Test func aLoneTaskHasNoSeparator() throws {
        #expect(!ReminderText.body(for: try reminder(items: [task()])).contains("·"))
    }
}
#endif
