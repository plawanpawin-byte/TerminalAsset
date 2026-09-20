#if canImport(SwiftData)
import Foundation
import SwiftData
import TerminalAssetDomain

/// App-owned record of a calendar occurrence. EventKit is only a reference; everything else lives here.
@Model
public final class TemporalEvent {
    /// Composite identity, see `EventIdentity`. Unique so a duplicate insert can never fork context.
    @Attribute(.unique) public var eventKey: String
    public var externalIdentifier: String?
    /// Last `eventIdentifier` seen. Volatile hint used only to re-link non-recurring events.
    public var lastEventIdentifier: String?
    public var calendarID: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var occurrenceDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var isRecurring: Bool
    public var fingerprint: String
    public var syncStateRaw: String
    public var lastSeenAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TemporalContext.event)
    public var context: TemporalContext?

    public var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .active }
        set { syncStateRaw = newValue.rawValue }
    }

    public init(key: EventKey, snapshot: CalendarEventSnapshot, seenAt: Date) {
        self.eventKey = key.rawValue
        self.externalIdentifier = snapshot.externalIdentifier
        self.lastEventIdentifier = snapshot.eventIdentifier
        self.calendarID = snapshot.calendarID
        self.title = snapshot.title
        self.startDate = snapshot.startDate
        self.endDate = snapshot.endDate
        self.occurrenceDate = snapshot.occurrenceDate
        self.isAllDay = snapshot.isAllDay
        self.location = snapshot.location
        self.isRecurring = snapshot.isRecurring
        self.fingerprint = EventIdentity.fingerprint(for: snapshot)
        self.syncStateRaw = SyncState.active.rawValue
        self.lastSeenAt = seenAt
    }

    /// `lastSeenAt` is refreshed at most this often, so a sync that changes nothing writes nothing.
    private static let seenRefreshInterval: TimeInterval = 6 * 3600

    /// Copies calendar-owned fields from a fresh snapshot. Context is never touched.
    ///
    /// Only fields that actually differ are assigned, so an unchanged event does not dirty the store (each sync
    /// re-reads the whole window, and rewriting every record every time wastes writes and triggers observers).
    /// Returns whether anything meaningful changed.
    @discardableResult
    func apply(_ snapshot: CalendarEventSnapshot, key: EventKey, seenAt: Date) -> Bool {
        var changed = false
        func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<TemporalEvent, Value>, _ value: Value) {
            if self[keyPath: keyPath] != value {
                self[keyPath: keyPath] = value
                changed = true
            }
        }
        assign(\.eventKey, key.rawValue)
        assign(\.externalIdentifier, snapshot.externalIdentifier)
        assign(\.lastEventIdentifier, snapshot.eventIdentifier)
        assign(\.calendarID, snapshot.calendarID)
        assign(\.title, snapshot.title)
        assign(\.startDate, snapshot.startDate)
        assign(\.endDate, snapshot.endDate)
        assign(\.occurrenceDate, snapshot.occurrenceDate)
        assign(\.isAllDay, snapshot.isAllDay)
        assign(\.location, snapshot.location)
        assign(\.isRecurring, snapshot.isRecurring)
        assign(\.fingerprint, EventIdentity.fingerprint(for: snapshot))
        assign(\.syncState, .active)
        if changed || seenAt.timeIntervalSince(lastSeenAt) >= Self.seenRefreshInterval {
            lastSeenAt = seenAt
        }
        return changed
    }

    var storedRecord: StoredEventRecord {
        StoredEventRecord(
            key: EventKey(rawValue: eventKey),
            lastEventIdentifier: lastEventIdentifier,
            fingerprint: fingerprint,
            isRecurring: isRecurring,
            startDate: startDate,
            endDate: endDate,
            state: syncState
        )
    }
}

/// The container of everything relevant to one event. Keeping the context separate from the event lets it
/// survive event re-linking and series moves.
@Model
public final class TemporalContext {
    public var createdAt: Date
    public var event: TemporalEvent?

    @Relationship(deleteRule: .cascade, inverse: \ContextItem.context)
    public var items: [ContextItem] = []

    public init(createdAt: Date) {
        self.createdAt = createdAt
    }
}

/// One note, link or task attached to a `TemporalContext`. Files, images and voice arrive with ingestion.
@Model
public final class ContextItem {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var title: String
    public var detail: String?
    public var urlString: String?
    public var isDone: Bool
    public var createdAt: Date
    /// Path of an attached file, relative to the shared attachments directory.
    public var fileName: String?
    public var context: TemporalContext?

    public var kind: ContextItemKind {
        get { ContextItemKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        kind: ContextItemKind,
        title: String,
        detail: String?,
        urlString: String?,
        fileName: String? = nil,
        createdAt: Date
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.detail = detail
        self.urlString = urlString
        self.fileName = fileName
        self.isDone = false
        self.createdAt = createdAt
    }

    var value: ContextItemValue {
        ContextItemValue(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            url: urlString.flatMap { URL(string: $0) },
            isDone: isDone,
            createdAt: createdAt,
            fileName: fileName
        )
    }
}

/// Something shared into the app (via the Share Extension) that is waiting for, or has found, its event.
/// Kept after handling so an attach can be undone; old entries are cleaned up by Context Decay later.
@Model
public final class InboxEntry {
    public enum Status: String, Sendable {
        case pending
        case attached
        case dismissed
    }

    /// Same as the manifest's id, so importing the same share twice cannot create a duplicate.
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var title: String
    public var text: String?
    public var urlString: String?
    public var payloadFileName: String?
    public var intentRaw: String
    public var receivedAt: Date
    /// Where the payload was stored, relative to the attachments directory.
    public var attachmentPath: String?
    public var statusRaw: String
    public var attachedEventKey: String?
    public var createdItemID: UUID?

    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(manifest: InboxManifest, attachmentPath: String?) {
        self.id = manifest.id
        self.kindRaw = manifest.kind.rawValue
        self.title = manifest.title
        self.text = manifest.text
        self.urlString = manifest.urlString
        self.payloadFileName = manifest.payloadFileName
        self.intentRaw = manifest.intent.rawValue
        self.receivedAt = manifest.receivedAt
        self.attachmentPath = attachmentPath
        self.statusRaw = Status.pending.rawValue
    }

    var manifest: InboxManifest {
        InboxManifest(
            id: id,
            draft: InboxDraft(
                kind: InboxPayloadKind(rawValue: kindRaw) ?? .text,
                title: title,
                text: text,
                urlString: urlString,
                payloadFileName: payloadFileName,
                intent: ShareIntent(rawValue: intentRaw) ?? .decide,
                receivedAt: receivedAt
            )
        )
    }
}
#endif
