#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600
private let window = DateInterval(start: base - 86_400, end: base + 3 * 86_400)

private func snapshot(_ id: String, _ title: String, start: Date, minutes: Int = 60) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: id, externalIdentifier: "x-\(id)", calendarID: "cal", title: title,
        startDate: start, endDate: start + TimeInterval(minutes) * minute, occurrenceDate: start,
        isAllDay: false, location: nil, isRecurring: false
    )
}

private struct Fixture {
    let store: ContextStore
    let inbox: SharedInbox
    let root: URL
    let running: EventKey
    let next: EventKey
}

@Suite("Inbox ingestion")
struct InboxIngestTests {
    private func makeFixture() async throws -> Fixture {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        let running = snapshot("run", "ISO Audit Preparation", start: base - 20 * minute)
        let next = snapshot("next", "Vendor security review", start: base + 40 * minute)
        _ = try await sync.apply(snapshots: [running, next], window: window, now: base)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalAssetCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Fixture(
            store: ContextStore(modelContainer: container),
            inbox: SharedInbox(rootURL: root),
            root: root,
            running: EventIdentity.key(for: running),
            next: EventIdentity.key(for: next)
        )
    }

    private func tempFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("payload".utf8).write(to: url)
        return url
    }

    @Test func sharedItemsBecomePendingWithASuggestion() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(
            kind: .url, title: "Audit guide", urlString: "https://iso.org/guide", receivedAt: base
        ))

        let report = try await f.store.ingest(from: f.inbox, now: base)
        let pending = try await f.store.pendingInbox()

        #expect(report.imported == 1)
        #expect(report.autoAttached.isEmpty)
        #expect(pending.count == 1)
        #expect(pending.first?.suggestion?.eventKey == f.running)
        #expect(try f.inbox.pending().items.isEmpty)
    }

    @Test func ingestingTwiceDoesNotDuplicate() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(kind: .text, title: "note", text: "note", receivedAt: base))

        _ = try await f.store.ingest(from: f.inbox, now: base)
        let second = try await f.store.ingest(from: f.inbox, now: base)

        #expect(second.imported == 0)
        #expect(try await f.store.pendingInbox().count == 1)
    }

    @Test func attachingALinkCreatesALinkItemOnTheEvent() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(
            kind: .url, title: "Audit guide", urlString: "https://iso.org/guide", receivedAt: base
        ))
        _ = try await f.store.ingest(from: f.inbox, now: base)
        let item = try #require(try await f.store.pendingInbox().first)

        try await f.store.attachInbox(id: item.id, to: f.running, now: base)

        let event = try await f.store.event(forKey: f.running)
        #expect(event?.items.map(\.kind) == [.link])
        #expect(event?.items.first?.url?.absoluteString == "https://iso.org/guide")
        #expect(try await f.store.pendingInbox().isEmpty)
    }

    @Test func attachingAFileStoresItAndAddsAFileItem() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let source = try tempFile(named: "Q3 vendor list.xlsx")
        try f.inbox.enqueue(InboxDraft(kind: .file, title: "Q3 vendor list.xlsx", receivedAt: base), payload: source)
        _ = try await f.store.ingest(from: f.inbox, now: base)
        let item = try #require(try await f.store.pendingInbox().first)

        try await f.store.attachInbox(id: item.id, to: f.next, now: base)

        let stored = try #require(try await f.store.event(forKey: f.next)?.items.first)
        #expect(stored.kind == .file)
        let path = try #require(stored.fileName)
        #expect(FileManager.default.fileExists(atPath: f.inbox.attachmentURL(for: path).path))
    }

    @Test func undoRemovesTheCreatedItemAndRestoresTheEntry() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(kind: .text, title: "note", text: "remember this", receivedAt: base))
        _ = try await f.store.ingest(from: f.inbox, now: base)
        let item = try #require(try await f.store.pendingInbox().first)
        try await f.store.attachInbox(id: item.id, to: f.running, now: base)

        try await f.store.restoreInbox(id: item.id)

        #expect(try await f.store.event(forKey: f.running)?.items.isEmpty == true)
        #expect(try await f.store.pendingInbox().count == 1)
    }

    @Test func dismissedItemsLeaveThePendingList() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(kind: .text, title: "n", text: "n", receivedAt: base))
        _ = try await f.store.ingest(from: f.inbox, now: base)
        let item = try #require(try await f.store.pendingInbox().first)

        try await f.store.dismissInbox(id: item.id)
        #expect(try await f.store.pendingInbox().isEmpty)

        try await f.store.restoreInbox(id: item.id)
        #expect(try await f.store.pendingInbox().count == 1)
    }

    @Test func currentEventChoiceAutoAttachesToTheEventRunningWhenShared() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(
            kind: .text, title: "idea", text: "idea", intent: .currentEvent, receivedAt: base
        ))

        let report = try await f.store.ingest(from: f.inbox, now: base + 3 * hour)

        #expect(report.autoAttached == [AutoAttachment(title: "idea", eventTitle: "ISO Audit Preparation")])
        #expect(try await f.store.pendingInbox().isEmpty)
        #expect(try await f.store.event(forKey: f.running)?.items.count == 1)
    }

    @Test func upcomingEventChoiceAttachesToTheNextEvent() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try f.inbox.enqueue(InboxDraft(
            kind: .url, title: "Portal", urlString: "https://example.com", intent: .upcomingEvent, receivedAt: base
        ))

        let report = try await f.store.ingest(from: f.inbox, now: base)

        #expect(report.autoAttached.map(\.eventTitle) == ["Vendor security review"])
    }

    @Test func explicitChoiceWithNoMatchingEventStaysPending() async throws {
        let f = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        // Shared long after every event has finished.
        try f.inbox.enqueue(InboxDraft(
            kind: .text, title: "late", text: "late", intent: .currentEvent, receivedAt: base + 10 * hour
        ))

        let report = try await f.store.ingest(from: f.inbox, now: base + 10 * hour)

        #expect(report.autoAttached.isEmpty)
        #expect(try await f.store.pendingInbox().count == 1)
    }
}
#endif
