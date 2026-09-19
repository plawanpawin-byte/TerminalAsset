import Foundation

/// Stable, app-owned identity of a `TemporalEvent`. Persisted as a plain string.
public struct EventKey: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: EventKey, rhs: EventKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Builds the composite identity used to link a `TemporalEvent` to an EventKit occurrence.
///
/// Key format:
/// - `ext:<externalIdentifier>|<occurrenceEpochSeconds>` when the calendar provides an external identifier.
/// - `fp:<fingerprint>` otherwise (calendar + normalized title + start).
///
/// `eventIdentifier` is deliberately NOT part of the key because EventKit may change it.
public enum EventIdentity {
    public static func key(for snapshot: CalendarEventSnapshot, disambiguator: String? = nil) -> EventKey {
        let base: String
        if let external = normalized(snapshot.externalIdentifier), !external.isEmpty {
            base = "ext:\(external)|\(epochSeconds(snapshot.occurrenceDate))"
        } else {
            base = "fp:\(fingerprint(for: snapshot))"
        }
        guard let disambiguator, !disambiguator.isEmpty else {
            return EventKey(rawValue: base)
        }
        return EventKey(rawValue: "\(base)|cal:\(disambiguator)")
    }

    /// Weak identity used only to re-link records whose key changed (for example the external identifier
    /// became available after the event was first seen).
    public static func fingerprint(for snapshot: CalendarEventSnapshot) -> String {
        let title = normalized(snapshot.title) ?? ""
        return "\(snapshot.calendarID)|\(title.lowercased())|\(epochSeconds(snapshot.startDate))"
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }
}
