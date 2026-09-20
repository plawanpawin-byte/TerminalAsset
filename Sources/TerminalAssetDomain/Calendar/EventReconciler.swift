import Foundation

public enum SyncState: String, Sendable, Codable {
    case active
    /// Not seen in the calendar although its time range is inside the synced window. Context is kept, never deleted.
    case missing
}

/// Persisted state of a `TemporalEvent`, reduced to what reconciliation needs.
public struct StoredEventRecord: Sendable, Hashable {
    public let key: EventKey
    public let lastEventIdentifier: String?
    public let fingerprint: String
    public let isRecurring: Bool
    public let startDate: Date
    public let endDate: Date
    public let state: SyncState

    public init(
        key: EventKey,
        lastEventIdentifier: String?,
        fingerprint: String,
        isRecurring: Bool,
        startDate: Date,
        endDate: Date,
        state: SyncState
    ) {
        self.key = key
        self.lastEventIdentifier = lastEventIdentifier
        self.fingerprint = fingerprint
        self.isRecurring = isRecurring
        self.startDate = startDate
        self.endDate = endDate
        self.state = state
    }
}

public enum EventMatchReason: Sendable, Hashable {
    case exactKey
    case eventIdentifier
    case fingerprint
}

public struct EventInsert: Sendable, Hashable {
    public let key: EventKey
    public let snapshot: CalendarEventSnapshot
}

public struct EventUpdate: Sendable, Hashable {
    public let existingKey: EventKey
    public let newKey: EventKey
    public let snapshot: CalendarEventSnapshot
    public let reason: EventMatchReason
    public let wasMissing: Bool

    public var isRekey: Bool { existingKey != newKey }
}

public struct ReconciliationPlan: Sendable, Hashable {
    public let inserts: [EventInsert]
    public let updates: [EventUpdate]
    public let markMissing: [EventKey]
}

/// Pure, deterministic matching of EventKit snapshots to stored records. No IO, no persistence types.
///
/// Matching passes, each one-to-one and each only applied to what earlier passes left unmatched:
/// 1. exact key (`externalIdentifier` + `occurrenceDate`, or fingerprint key)
/// 2. `eventIdentifier`, non-recurring events only, because a series shares one identifier across occurrences
/// 3. fingerprint, only when it is unambiguous on both sides
///
/// Stored records left unmatched become `missing` only if their time range overlaps `window`;
/// records outside the window were simply not queried and are left untouched.
public enum EventReconciler {
    public static func reconcile(
        snapshots: [CalendarEventSnapshot],
        stored: [StoredEventRecord],
        window: DateInterval
    ) -> ReconciliationPlan {
        var remaining = assignKeys(to: snapshots)
        var unclaimed = Dictionary(stored.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var updates: [EventUpdate] = []

        func claim(_ index: Int, _ record: StoredEventRecord, reason: EventMatchReason) {
            let item = remaining[index]
            updates.append(EventUpdate(
                existingKey: record.key,
                newKey: item.key,
                snapshot: item.snapshot,
                reason: reason,
                wasMissing: record.state == .missing
            ))
            unclaimed[record.key] = nil
            remaining[index].isMatched = true
        }

        // Pass 1: exact key.
        for index in remaining.indices {
            if let record = unclaimed[remaining[index].key] {
                claim(index, record, reason: .exactKey)
            }
        }

        // Pass 2: eventIdentifier, non-recurring only.
        var byIdentifier: [String: [EventKey]] = [:]
        for record in unclaimed.values where !record.isRecurring {
            if let identifier = record.lastEventIdentifier {
                byIdentifier[identifier, default: []].append(record.key)
            }
        }
        for index in remaining.indices where !remaining[index].isMatched {
            let snapshot = remaining[index].snapshot
            guard !snapshot.isRecurring,
                  let identifier = snapshot.eventIdentifier,
                  let candidates = byIdentifier[identifier],
                  candidates.count == 1,
                  let record = unclaimed[candidates[0]]
            else { continue }
            claim(index, record, reason: .eventIdentifier)
        }

        // Pass 3: fingerprint, unambiguous on both sides.
        var byFingerprint: [String: [EventKey]] = [:]
        for record in unclaimed.values {
            byFingerprint[record.fingerprint, default: []].append(record.key)
        }
        var snapshotFingerprintCounts: [String: Int] = [:]
        for item in remaining where !item.isMatched {
            snapshotFingerprintCounts[EventIdentity.fingerprint(for: item.snapshot), default: 0] += 1
        }
        for index in remaining.indices where !remaining[index].isMatched {
            let fingerprint = EventIdentity.fingerprint(for: remaining[index].snapshot)
            guard snapshotFingerprintCounts[fingerprint] == 1,
                  let candidates = byFingerprint[fingerprint],
                  candidates.count == 1,
                  let record = unclaimed[candidates[0]]
            else { continue }
            claim(index, record, reason: .fingerprint)
        }

        let inserts = remaining
            .filter { !$0.isMatched }
            .map { EventInsert(key: $0.key, snapshot: $0.snapshot) }

        let missing = unclaimed.values
            .filter { $0.state != .missing && overlaps($0, window: window) }
            .map(\.key)
            .sorted()

        return ReconciliationPlan(inserts: inserts, updates: updates, markMissing: missing)
    }

    // MARK: - Key assignment

    private struct KeyedSnapshot {
        let key: EventKey
        let snapshot: CalendarEventSnapshot
        var isMatched = false
    }

    /// Sorts deterministically, then resolves key collisions (same external ID + occurrence in two calendars)
    /// by qualifying the key with the calendar. Events that are still indistinguishable (two "Standup"s at the same
    /// time in one calendar) get an ordinal, so each keeps its own context instead of one silently disappearing.
    private static func assignKeys(to snapshots: [CalendarEventSnapshot]) -> [KeyedSnapshot] {
        let ordered = snapshots.sorted { lhs, rhs in
            if lhs.calendarID != rhs.calendarID { return lhs.calendarID < rhs.calendarID }
            let lhsID = lhs.eventIdentifier ?? ""
            let rhsID = rhs.eventIdentifier ?? ""
            if lhsID != rhsID { return lhsID < rhsID }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            // Fully ambiguous events still need a stable order so the ordinals below are assigned consistently.
            if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
            return lhs.title < rhs.title
        }
        var seen = Set<EventKey>()
        var result: [KeyedSnapshot] = []
        result.reserveCapacity(ordered.count)
        for snapshot in ordered {
            var key = EventIdentity.key(for: snapshot)
            if seen.contains(key) {
                key = EventIdentity.key(for: snapshot, disambiguator: snapshot.calendarID)
            }
            var ordinal = 1
            let base = key
            while !seen.insert(key).inserted {
                ordinal += 1
                key = EventKey(rawValue: "\(base.rawValue)|n:\(ordinal)")
            }
            result.append(KeyedSnapshot(key: key, snapshot: snapshot))
        }
        return result
    }

    private static func overlaps(_ record: StoredEventRecord, window: DateInterval) -> Bool {
        record.startDate < window.end && record.endDate > window.start
    }
}
