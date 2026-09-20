#if canImport(SwiftData)
import Foundation
import SwiftData
import TerminalAssetDomain

/// Reads events with their context and edits context items, all off the main actor.
/// Only `Sendable` values cross its boundary.
@ModelActor
public actor ContextStore {
    /// Events overlapping `start..<end`, sorted by start, each with its context items.
    public func events(from start: Date, to end: Date) throws -> [TimelineEvent] {
        try perform {
            let descriptor = FetchDescriptor<TemporalEvent>(
                predicate: #Predicate { $0.startDate < end && $0.endDate > start },
                sortBy: [SortDescriptor(\.startDate)]
            )
            return try modelContext.fetch(descriptor).map(Self.timelineEvent(from:))
        }
    }

    /// Every stored event, oldest first, for exporting the user's data.
    public func allEvents() throws -> [TimelineEvent] {
        try perform {
            let descriptor = FetchDescriptor<TemporalEvent>(sortBy: [SortDescriptor(\.startDate)])
            return try modelContext.fetch(descriptor).map(Self.timelineEvent(from:))
        }
    }

    /// Deletes everything the app stored: events, their context items and the share history. The calendar itself
    /// is untouched, so events reappear (without context) at the next sync. Only used by "Delete all data".
    public func eraseEverything() throws {
        // Object by object, not `delete(model:)`: the batch delete cannot cross the required event → context → item
        // relationships and fails with a constraint violation.
        try perform {
            for item in try modelContext.fetch(FetchDescriptor<ContextItem>()) { modelContext.delete(item) }
            for context in try modelContext.fetch(FetchDescriptor<TemporalContext>()) { modelContext.delete(context) }
            for event in try modelContext.fetch(FetchDescriptor<TemporalEvent>()) { modelContext.delete(event) }
            for entry in try modelContext.fetch(FetchDescriptor<InboxEntry>()) { modelContext.delete(entry) }
            try modelContext.save()
        }
    }

    public func event(forKey key: EventKey) throws -> TimelineEvent? {
        try perform {
            try fetchEvent(key).map(Self.timelineEvent(from:))
        }
    }

    @discardableResult
    public func addItem(to key: EventKey, draft: ContextItemDraft, now: Date) throws -> ContextItemValue {
        let valid: ValidatedContextItem
        do {
            valid = try draft.validated()
        } catch let error as ContextValidationError {
            throw ContextStoreError.invalidItem(error)
        } catch {
            throw ContextStoreError.persistence(reason: error.localizedDescription)
        }

        return try perform {
            guard let event = try fetchEvent(key) else { throw ContextStoreError.eventNotFound }
            let item = insertItem(valid, into: event, now: now)
            try modelContext.save()
            return item.value
        }
    }

    public func setTaskDone(id: UUID, isDone: Bool) throws {
        try perform {
            guard let item = try fetchItem(id) else { throw ContextStoreError.itemNotFound }
            guard item.kind == .task else { throw ContextStoreError.notATask }
            item.isDone = isDone
            try modelContext.save()
        }
    }

    public func deleteItem(id: UUID) throws {
        try perform {
            guard let item = try fetchItem(id) else { throw ContextStoreError.itemNotFound }
            modelContext.delete(item)
            try modelContext.save()
        }
    }

    // MARK: - Private

    /// Creates the item inside the event's context (creating the context if needed). Does not save.
    func insertItem(_ valid: ValidatedContextItem, into event: TemporalEvent, now: Date) -> ContextItem {
        let context = event.context ?? TemporalContext(createdAt: now)
        if event.context == nil { event.context = context }

        let item = ContextItem(
            kind: valid.kind,
            title: valid.title,
            detail: valid.detail,
            urlString: valid.url?.absoluteString,
            fileName: valid.fileName,
            createdAt: now
        )
        modelContext.insert(item)
        item.context = context
        return item
    }

    func fetchEvent(_ key: EventKey) throws -> TemporalEvent? {
        let raw = key.rawValue
        var descriptor = FetchDescriptor<TemporalEvent>(predicate: #Predicate { $0.eventKey == raw })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchItem(_ id: UUID) throws -> ContextItem? {
        var descriptor = FetchDescriptor<ContextItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Runs `body`, rolls back on failure and maps unknown errors to `ContextStoreError.persistence`.
    func perform<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ContextStoreError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw ContextStoreError.persistence(reason: error.localizedDescription)
        }
    }

    private static func timelineEvent(from model: TemporalEvent) -> TimelineEvent {
        let items = (model.context?.items ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.value)
        return TimelineEvent(
            key: EventKey(rawValue: model.eventKey),
            title: model.title,
            startDate: model.startDate,
            endDate: model.endDate,
            isAllDay: model.isAllDay,
            location: model.location,
            syncState: model.syncState,
            items: items
        )
    }
}
#endif
