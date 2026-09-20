#if canImport(SwiftData)
import Foundation
import SwiftData
import TerminalAssetDomain

public struct SyncReport: Sendable, Equatable {
    public let inserted: Int
    public let updated: Int
    /// Records whose key changed (re-linked instead of orphaned).
    public let relinked: Int
    public let restored: Int
    public let markedMissing: Int
}

/// Applies calendar snapshots to SwiftData off the main actor. Never deletes an event or its context.
@ModelActor
public actor CalendarSyncActor {
    public func apply(
        snapshots: [CalendarEventSnapshot],
        window: DateInterval,
        now: Date
    ) throws -> SyncReport {
        do {
            let candidates = try storedCandidates(snapshots: snapshots, window: window)
            let byKey = Dictionary(
                candidates.map { ($0.eventKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let plan = EventReconciler.reconcile(
                snapshots: snapshots,
                stored: candidates.map(\.storedRecord),
                window: window
            )

            // Rekeying can swap keys between records, so resolve every model before mutating any key.
            let resolved = plan.updates.compactMap { update in
                byKey[update.existingKey.rawValue].map { ($0, update) }
            }
            var updated = 0
            var relinked = 0
            var restored = 0
            for (model, update) in resolved {
                if model.apply(update.snapshot, key: update.newKey, seenAt: now) { updated += 1 }
                if update.isRekey { relinked += 1 }
                if update.wasMissing { restored += 1 }
            }

            for insert in plan.inserts {
                let event = TemporalEvent(key: insert.key, snapshot: insert.snapshot, seenAt: now)
                event.context = TemporalContext(createdAt: now)
                modelContext.insert(event)
            }

            let missingKeys = Set(plan.markMissing.map(\.rawValue))
            for model in candidates where missingKeys.contains(model.eventKey) {
                model.syncState = .missing
            }

            try modelContext.save()
            return SyncReport(
                inserted: plan.inserts.count,
                updated: updated,
                relinked: relinked,
                restored: restored,
                markedMissing: plan.markMissing.count
            )
        } catch {
            modelContext.rollback()
            throw SyncError.persistence(reason: error.localizedDescription)
        }
    }

    /// Fetches only what reconciliation can match: records overlapping the window, records already `missing`,
    /// and records whose key appears in the incoming snapshots (an occurrence moved into the window).
    private func storedCandidates(
        snapshots: [CalendarEventSnapshot],
        window: DateInterval
    ) throws -> [TemporalEvent] {
        let windowStart = window.start
        let windowEnd = window.end
        let missingRaw = SyncState.missing.rawValue
        let incomingKeys = snapshots.map { EventIdentity.key(for: $0).rawValue }

        let overlapping = try modelContext.fetch(FetchDescriptor<TemporalEvent>(
            predicate: #Predicate { $0.startDate < windowEnd && $0.endDate > windowStart }
        ))
        let missing = try modelContext.fetch(FetchDescriptor<TemporalEvent>(
            predicate: #Predicate { $0.syncStateRaw == missingRaw }
        ))
        let incoming = try modelContext.fetch(FetchDescriptor<TemporalEvent>(
            predicate: #Predicate { incomingKeys.contains($0.eventKey) }
        ))

        var unique: [String: TemporalEvent] = [:]
        for model in overlapping + missing + incoming {
            unique[model.eventKey] = model
        }
        return Array(unique.values)
    }
}
#endif
