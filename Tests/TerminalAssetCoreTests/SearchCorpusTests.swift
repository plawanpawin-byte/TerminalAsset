#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
private let window = DateInterval(start: base - 200 * day, end: base + 200 * day)

private func snapshot(_ id: String, _ title: String, start: Date) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: id, externalIdentifier: "x-\(id)", calendarID: "cal", title: title,
        startDate: start, endDate: start + hour, occurrenceDate: start,
        isAllDay: false, location: "Room 4", isRecurring: false
    )
}

@Suite("Search corpus")
struct SearchCorpusTests {
    private func makeStore(_ snapshots: [CalendarEventSnapshot]) async throws -> ContextStore {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        _ = try await sync.apply(snapshots: snapshots, window: window, now: base)
        return ContextStore(modelContainer: container)
    }

    @Test func eventsAndTheirItemsBecomeDocuments() async throws {
        let audit = snapshot("a", "ISO Audit Preparation", start: base)
        let store = try await makeStore([audit])
        let key = EventIdentity.key(for: audit)
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .task, title: "Send agenda"), now: base)
        try await store.addItem(
            to: key,
            draft: ContextItemDraft(kind: .link, title: "Guide", urlString: "https://iso.org/guide"),
            now: base
        )

        let documents = try await store.searchCorpus(now: base)

        #expect(documents.count == 3)
        #expect(documents.contains { $0.kind == .event && $0.body == "Room 4" })
        #expect(documents.first { $0.kind == .link }?.body == "https://iso.org/guide")
        #expect(documents.allSatisfy { $0.eventKey == key })
    }

    @Test func searchFindsAContextItemThroughItsEventName() async throws {
        let audit = snapshot("a", "ISO Audit Preparation", start: base)
        let store = try await makeStore([audit])
        try await store.addItem(
            to: EventIdentity.key(for: audit),
            draft: ContextItemDraft(kind: .note, title: "Bring evidence"),
            now: base
        )

        let documents = try await store.searchCorpus(now: base)
        let hits = SearchEngine.search("audit", scope: .notes, in: documents, now: base)

        #expect(hits.map(\.document.title) == ["Bring evidence"])
    }

    @Test func farAwayEventsWithoutContextAreLeftOut() async throws {
        let far = snapshot("far", "Old offsite", start: base - 150 * day)
        let store = try await makeStore([far])

        #expect(try await store.searchCorpus(now: base).isEmpty)
    }

    @Test func contextOfADisappearedEventStaysSearchable() async throws {
        let audit = snapshot("a", "ISO Audit Preparation", start: base)
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        let store = ContextStore(modelContainer: container)
        _ = try await sync.apply(snapshots: [audit], window: window, now: base)
        try await store.addItem(
            to: EventIdentity.key(for: audit),
            draft: ContextItemDraft(kind: .note, title: "Keep me"),
            now: base
        )

        _ = try await sync.apply(snapshots: [], window: window, now: base + hour)

        let documents = try await store.searchCorpus(now: base + hour)
        #expect(documents.map(\.kind) == [.note])
        #expect(documents.first?.title == "Keep me")
    }
}
#endif
