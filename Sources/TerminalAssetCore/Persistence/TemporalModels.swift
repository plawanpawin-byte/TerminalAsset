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

    /// Copies calendar-owned fields from a fresh snapshot. Context is never touched.
    func apply(_ snapshot: CalendarEventSnapshot, key: EventKey, seenAt: Date) {
        eventKey = key.rawValue
        externalIdentifier = snapshot.externalIdentifier
        lastEventIdentifier = snapshot.eventIdentifier
        calendarID = snapshot.calendarID
        title = snapshot.title
        startDate = snapshot.startDate
        endDate = snapshot.endDate
        occurrenceDate = snapshot.occurrenceDate
        isAllDay = snapshot.isAllDay
        location = snapshot.location
        isRecurring = snapshot.isRecurring
        fingerprint = EventIdentity.fingerprint(for: snapshot)
        syncState = .active
        lastSeenAt = seenAt
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

/// The container of everything relevant to one event. Items (files, notes, links, tasks) attach here in the
/// next slice; keeping the context separate from the event lets it survive event re-linking and series moves.
@Model
public final class TemporalContext {
    public var createdAt: Date
    public var event: TemporalEvent?

    public init(createdAt: Date) {
        self.createdAt = createdAt
    }
}
#endif
