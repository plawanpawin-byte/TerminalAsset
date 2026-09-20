#if canImport(SwiftData)
import Foundation
import SwiftData
import TerminalAssetDomain

/// Inbox operations live on `ContextStore` (same actor, same context) so attaching an item and marking its
/// inbox entry as handled happen in a single save.
extension ContextStore {
    /// Imports everything the Share Extension queued, then clears the queue.
    ///
    /// Idempotent: an item whose id is already stored is only removed from the queue. The queue entry is deleted
    /// after the database save, so a crash in between re-imports harmlessly instead of losing the share.
    /// Items shared with an explicit "current" or "upcoming" choice are attached right away, resolved against the
    /// calendar at the moment they were shared.
    public func ingest(from inbox: SharedInbox, now: Date) throws -> IngestReport {
        let scan: (items: [PendingInboxItem], rejected: Int)
        do {
            scan = try inbox.pending()
        } catch {
            throw ContextStoreError.persistence(reason: error.localizedDescription)
        }
        guard !scan.items.isEmpty else {
            return IngestReport(imported: 0, autoAttached: [], rejected: scan.rejected)
        }

        var imported = 0
        var autoAttached: [AutoAttachment] = []
        var handled: [UUID] = []

        try perform {
            for item in scan.items {
                let manifest = item.manifest
                if try fetchEntry(manifest.id) != nil {
                    handled.append(manifest.id)
                    continue
                }

                // A file that cannot be stored right now (disk full, say) stays in the queue for the next launch;
                // it must not block the shares behind it.
                let attachmentPath: String?
                do {
                    attachmentPath = try inbox.storeAttachment(for: item)
                } catch {
                    continue
                }
                let entry = InboxEntry(manifest: manifest, attachmentPath: attachmentPath)
                modelContext.insert(entry)
                imported += 1
                handled.append(manifest.id)

                guard manifest.intent != .decide else { continue }
                let nearby = try events(
                    from: manifest.receivedAt.addingTimeInterval(-86_400),
                    to: manifest.receivedAt.addingTimeInterval(2 * 86_400)
                )
                if let target = EventSuggester.resolve(intent: manifest.intent, at: manifest.receivedAt, events: nearby) {
                    // If it cannot be attached (say the title is too long) it simply stays pending in the Inbox.
                    // `attach` fails before changing anything, so nothing is left half done.
                    do {
                        _ = try attach(entry, toEventKey: target.key, now: now)
                        autoAttached.append(AutoAttachment(title: manifest.title, eventTitle: target.title))
                    } catch ContextStoreError.invalidItem {
                        continue
                    } catch ContextStoreError.eventNotFound {
                        continue
                    }
                }
            }
            try modelContext.save()
        }

        for id in handled { inbox.remove(id: id) }
        return IngestReport(imported: imported, autoAttached: autoAttached, rejected: scan.rejected)
    }

    /// Items waiting for an event, newest first, each with a deterministic suggestion when one is confident enough.
    public func pendingInbox() throws -> [InboxItemValue] {
        try perform {
            let pendingRaw = InboxEntry.Status.pending.rawValue
            let descriptor = FetchDescriptor<InboxEntry>(
                predicate: #Predicate { $0.statusRaw == pendingRaw },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
            let entries = try modelContext.fetch(descriptor)
            guard let newest = entries.first?.receivedAt, let oldest = entries.last?.receivedAt else { return [] }

            let nearby = try events(from: oldest.addingTimeInterval(-86_400), to: newest.addingTimeInterval(2 * 86_400))
            return entries.map { entry in
                let manifest = entry.manifest
                return InboxItemValue(
                    id: entry.id,
                    kind: manifest.kind,
                    title: manifest.title,
                    subtitle: manifest.subtitle,
                    receivedAt: entry.receivedAt,
                    suggestion: EventSuggester.suggest(
                        text: manifest.searchableText,
                        at: entry.receivedAt,
                        events: nearby
                    )
                )
            }
        }
    }

    @discardableResult
    public func attachInbox(id: UUID, to key: EventKey, now: Date) throws -> ContextItemValue {
        try perform {
            guard let entry = try fetchEntry(id) else { throw ContextStoreError.itemNotFound }
            let created = try attach(entry, toEventKey: key, now: now)
            try modelContext.save()
            return created
        }
    }

    public func dismissInbox(id: UUID) throws {
        try perform {
            guard let entry = try fetchEntry(id) else { throw ContextStoreError.itemNotFound }
            entry.status = .dismissed
            try modelContext.save()
        }
    }

    /// Undoes an attach or a dismiss: the entry is pending again and any context item it created is removed.
    public func restoreInbox(id: UUID) throws {
        try perform {
            guard let entry = try fetchEntry(id) else { throw ContextStoreError.itemNotFound }
            if let itemID = entry.createdItemID, let item = try fetchItem(itemID) {
                modelContext.delete(item)
            }
            entry.status = .pending
            entry.attachedEventKey = nil
            entry.createdItemID = nil
            try modelContext.save()
        }
    }

    // MARK: - Private

    private func fetchEntry(_ id: UUID) throws -> InboxEntry? {
        var descriptor = FetchDescriptor<InboxEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Turns the entry into a context item on the event and marks the entry attached. Does not save.
    private func attach(_ entry: InboxEntry, toEventKey key: EventKey, now: Date) throws -> ContextItemValue {
        // Attaching twice (a double tap, or an entry that was already attached automatically) would create a second
        // item and lose track of the first.
        guard entry.status == .pending else { throw ContextStoreError.alreadyHandled }
        guard let event = try fetchEvent(key) else { throw ContextStoreError.eventNotFound }
        let draft = entry.manifest.contextDraft(attachmentPath: entry.attachmentPath)

        let valid: ValidatedContextItem
        do {
            valid = try draft.validated()
        } catch let error as ContextValidationError {
            throw ContextStoreError.invalidItem(error)
        } catch {
            throw ContextStoreError.persistence(reason: error.localizedDescription)
        }

        let item = insertItem(valid, into: event, now: now)
        entry.status = .attached
        entry.attachedEventKey = key.rawValue
        entry.createdItemID = item.id
        return item.value
    }
}
#endif
