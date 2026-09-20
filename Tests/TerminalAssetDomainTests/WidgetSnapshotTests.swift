import Foundation
import Testing
@testable import TerminalAssetDomain

/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)
private let hour: TimeInterval = 3600

private func task(done: Bool) -> ContextItemValue {
    ContextItemValue(id: UUID(), kind: .task, title: "t", detail: nil, url: nil, isDone: done, createdAt: now)
}

private func event(
    _ title: String,
    from offset: TimeInterval,
    lasting duration: TimeInterval = hour,
    allDay: Bool = false,
    state: SyncState = .active,
    items: [ContextItemValue] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"), title: title,
        startDate: now + offset, endDate: now + offset + duration,
        isAllDay: allDay, location: "HQ", syncState: state, items: items
    )
}

@Suite("WidgetSnapshot")
struct WidgetSnapshotTests {
    @Test func keepsOnlyTimedActiveEventsThatHaveNotEnded() {
        let snapshot = WidgetSnapshot.make(
            from: [
                event("Past", from: -3 * hour),
                event("AllDay", from: -hour, lasting: 24 * hour, allDay: true),
                event("Gone", from: hour, state: .missing),
                event("Now", from: -hour / 2),
                event("Later", from: 2 * hour)
            ],
            now: now
        )
        #expect(snapshot.entries.map(\.title) == ["Now", "Later"])
    }

    @Test func isSortedSoonestFirstAndLimited() {
        let events = (1...10).map { event("E\($0)", from: Double(11 - $0) * hour) }
        let snapshot = WidgetSnapshot.make(from: events, now: now, limit: 3)
        #expect(snapshot.entries.map(\.title) == ["E10", "E9", "E8"])
    }

    @Test func carriesWhatIsWaitingForTheUser() throws {
        let snapshot = WidgetSnapshot.make(
            from: [event("Audit", from: hour, items: [task(done: false), task(done: true)])], now: now
        )
        let entry = try #require(snapshot.entries.first)
        #expect(entry.openTasks == 1)
        #expect(entry.hasContext)
        #expect(entry.location == "HQ")
    }

    @Test func anEventWithNothingAttachedSaysSo() throws {
        let snapshot = WidgetSnapshot.make(from: [event("Bare", from: hour)], now: now)
        #expect(try #require(snapshot.entries.first).hasContext == false)
    }

    // MARK: Reading at a moment

    @Test func currentIsTheEventInProgress() {
        let snapshot = WidgetSnapshot.make(
            from: [event("Running", from: -hour / 2), event("Next", from: hour)], now: now
        )
        #expect(snapshot.current(at: now)?.title == "Running")
        #expect(snapshot.upcoming(at: now).map(\.title) == ["Next"])
    }

    @Test func theSnapshotAgesCorrectlyWithoutTheApp() {
        let snapshot = WidgetSnapshot.make(
            from: [event("First", from: hour), event("Second", from: 3 * hour)], now: now
        )
        // An hour later "First" has started; two hours after that it is over and "Second" runs.
        #expect(snapshot.current(at: now + hour)?.title == "First")
        #expect(snapshot.current(at: now + 2 * hour) == nil)
        #expect(snapshot.current(at: now + 3 * hour)?.title == "Second")
        #expect(snapshot.upcoming(at: now + 3 * hour).isEmpty)
    }

    @Test func changeDatesAreEveryStartAndEndAfterNow() {
        let snapshot = WidgetSnapshot.make(
            from: [event("A", from: -hour / 2), event("B", from: hour)], now: now
        )
        #expect(snapshot.changeDates(after: now) == [
            now + hour / 2,   // A ends
            now + hour,       // B starts
            now + 2 * hour    // B ends
        ])
    }

    @Test func overlappingEventsShowTheLatestStartedAsCurrent() {
        let snapshot = WidgetSnapshot.make(
            from: [event("Long", from: -2 * hour, lasting: 4 * hour), event("Short", from: -hour / 2)], now: now
        )
        #expect(snapshot.current(at: now)?.title == "Short")
    }

    // MARK: Coding

    @Test func roundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot.make(from: [event("Audit", from: hour, items: [task(done: false)])], now: now)
        #expect(try WidgetSnapshot.decoded(from: snapshot.encoded()) == snapshot)
    }

    @Test func writesAndReadsAFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = WidgetSnapshot.make(from: [event("Audit", from: hour)], now: now)

        try snapshot.write(to: directory)

        #expect(WidgetSnapshot.read(from: directory) == snapshot)
    }

    @Test func aMissingOrCorruptFileReadsAsNothing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(WidgetSnapshot.read(from: directory) == nil)

        try Data("not json".utf8).write(to: directory.appendingPathComponent(WidgetSnapshot.fileName))
        #expect(WidgetSnapshot.read(from: directory) == nil)
    }
}
