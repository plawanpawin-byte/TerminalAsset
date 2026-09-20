#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import TerminalAssetDomain
@testable import TerminalAssetCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600
private let window = DateInterval(start: base - 86_400, end: base + 86_400)

private let snapshot = CalendarEventSnapshot(
    eventIdentifier: "e1",
    externalIdentifier: "x1",
    calendarID: "cal",
    title: "ISO Audit Prep",
    startDate: base,
    endDate: base + hour,
    occurrenceDate: base,
    isAllDay: false,
    location: "Room 4",
    isRecurring: false
)

@Suite("ContextStore")
struct ContextStoreTests {
    private func makeStores() async throws -> (ContextStore, EventKey) {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        _ = try await sync.apply(snapshots: [snapshot], window: window, now: base)
        return (ContextStore(modelContainer: container), EventIdentity.key(for: snapshot))
    }

    @Test func eventsAreReturnedWithTheirItems() async throws {
        let (store, key) = try await makeStores()
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .task, title: "Send agenda"), now: base)

        let events = try await store.events(from: base - hour, to: base + 2 * hour)

        #expect(events.count == 1)
        #expect(events.first?.location == "Room 4")
        #expect(events.first?.items.map(\.title) == ["Send agenda"])
        #expect(events.first?.summary.openTasks == 1)
    }

    @Test func aNoteCanBeEdited() async throws {
        let (store, key) = try await makeStores()
        let note = try await store.addItem(
            to: key, draft: ContextItemDraft(kind: .note, title: "Old", detail: "before"), now: base
        )

        try await store.updateItem(id: note.id, with: ContextItemDraft(kind: .note, title: " New ", detail: "after"))

        let item = try #require(try await store.event(forKey: key)?.items.first)
        #expect(item.title == "New")
        #expect(item.detail == "after")
        #expect(item.id == note.id)
    }

    @Test func editingATaskKeepsItsDoneState() async throws {
        let (store, key) = try await makeStores()
        let task = try await store.addItem(to: key, draft: ContextItemDraft(kind: .task, title: "Send"), now: base)
        try await store.setTaskDone(id: task.id, isDone: true)

        try await store.updateItem(id: task.id, with: ContextItemDraft(kind: .task, title: "Send agenda"))

        let item = try #require(try await store.event(forKey: key)?.items.first)
        #expect(item.title == "Send agenda")
        #expect(item.isDone)
    }

    @Test func aLinkCanBeEditedAndIsChecked() async throws {
        let (store, key) = try await makeStores()
        let link = try await store.addItem(
            to: key, draft: ContextItemDraft(kind: .link, urlString: "example.com/a"), now: base
        )

        try await store.updateItem(
            id: link.id, with: ContextItemDraft(kind: .link, title: "Plan", urlString: "example.com/b")
        )
        let item = try #require(try await store.event(forKey: key)?.items.first)
        #expect(item.title == "Plan")
        #expect(item.url?.host() == "example.com")
        #expect(item.url?.path == "/b")

        await #expect(throws: ContextStoreError.invalidItem(.invalidURL)) {
            try await store.updateItem(id: link.id, with: ContextItemDraft(kind: .link, urlString: "not a url"))
        }
    }

    @Test func theKindCannotChangeAndMissingItemsAreReported() async throws {
        let (store, key) = try await makeStores()
        let note = try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "N"), now: base)

        await #expect(throws: ContextStoreError.invalidItem(.unsupportedKind)) {
            try await store.updateItem(id: note.id, with: ContextItemDraft(kind: .task, title: "T"))
        }
        await #expect(throws: ContextStoreError.itemNotFound) {
            try await store.updateItem(id: UUID(), with: ContextItemDraft(kind: .note, title: "N"))
        }
        await #expect(throws: ContextStoreError.invalidItem(.emptyTitle)) {
            try await store.updateItem(id: note.id, with: ContextItemDraft(kind: .note, title: " "))
        }
    }

    @Test func allEventsReturnsEveryStoredEventWithItsItems() async throws {
        let (store, key) = try await makeStores()
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "Remember"), now: base)

        let events = try await store.allEvents()

        #expect(events.map(\.key) == [key])
        #expect(events.first?.items.map(\.title) == ["Remember"])
    }

    @Test func eraseEverythingRemovesEventsAndContext() async throws {
        let (store, key) = try await makeStores()
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .task, title: "Send agenda"), now: base)

        try await store.eraseEverything()

        #expect(try await store.allEvents().isEmpty)
        #expect(try await store.event(forKey: key) == nil)
    }

    @Test func eraseEverythingOnAnEmptyStoreIsHarmless() async throws {
        let container = try TemporalStore.makeContainer(inMemory: true)
        try await ContextStore(modelContainer: container).eraseEverything()
    }

    @Test func eventsReturnAfterAnEraseWithoutContext() async throws {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        let store = ContextStore(modelContainer: container)
        _ = try await sync.apply(snapshots: [snapshot], window: window, now: base)
        let key = EventIdentity.key(for: snapshot)
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "Old"), now: base)

        try await store.eraseEverything()
        _ = try await sync.apply(snapshots: [snapshot], window: window, now: base + hour)

        let event = try await store.event(forKey: key)
        #expect(event != nil)
        #expect(event?.items.isEmpty == true)
    }

    @Test func eventsOutsideTheRangeAreNotReturned() async throws {
        let (store, _) = try await makeStores()
        let events = try await store.events(from: base + 5 * hour, to: base + 6 * hour)
        #expect(events.isEmpty)
    }

    @Test func invalidDraftIsRejectedWithATypedError() async throws {
        let (store, key) = try await makeStores()
        await #expect(throws: ContextStoreError.invalidItem(.emptyTitle)) {
            try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: " "), now: base)
        }
        #expect(try await store.event(forKey: key)?.items.isEmpty == true)
    }

    @Test func addingToAnUnknownEventFails() async throws {
        let (store, _) = try await makeStores()
        await #expect(throws: ContextStoreError.eventNotFound) {
            try await store.addItem(
                to: EventKey(rawValue: "nope"),
                draft: ContextItemDraft(kind: .note, title: "x"),
                now: base
            )
        }
    }

    @Test func tasksCanBeCompletedButNotesCannot() async throws {
        let (store, key) = try await makeStores()
        let task = try await store.addItem(to: key, draft: ContextItemDraft(kind: .task, title: "T"), now: base)
        let note = try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "N"), now: base)

        try await store.setTaskDone(id: task.id, isDone: true)
        #expect(try await store.event(forKey: key)?.summary.openTasks == 0)

        await #expect(throws: ContextStoreError.notATask) {
            try await store.setTaskDone(id: note.id, isDone: true)
        }
    }

    @Test func deletingAnItemRemovesOnlyThatItem() async throws {
        let (store, key) = try await makeStores()
        let first = try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "A"), now: base)
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "B"), now: base + 1)

        try await store.deleteItem(id: first.id)

        #expect(try await store.event(forKey: key)?.items.map(\.title) == ["B"])
    }

    @Test func contextSurvivesAResyncThatMovesTheEvent() async throws {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncActor(modelContainer: container)
        let store = ContextStore(modelContainer: container)
        let recurring = CalendarEventSnapshot(
            eventIdentifier: "s", externalIdentifier: "series", calendarID: "cal", title: "Weekly",
            startDate: base, endDate: base + hour, occurrenceDate: base,
            isAllDay: false, location: nil, isRecurring: true
        )
        _ = try await sync.apply(snapshots: [recurring], window: window, now: base)
        let key = EventIdentity.key(for: recurring)
        try await store.addItem(to: key, draft: ContextItemDraft(kind: .note, title: "Keep me"), now: base)

        let moved = CalendarEventSnapshot(
            eventIdentifier: "s", externalIdentifier: "series", calendarID: "cal", title: "Weekly",
            startDate: base + 2 * hour, endDate: base + 3 * hour, occurrenceDate: base,
            isAllDay: false, location: nil, isRecurring: true
        )
        _ = try await sync.apply(snapshots: [moved], window: window, now: base + hour)

        let event = try await store.event(forKey: key)
        #expect(event?.startDate == base + 2 * hour)
        #expect(event?.items.map(\.title) == ["Keep me"])
    }
}
#endif
