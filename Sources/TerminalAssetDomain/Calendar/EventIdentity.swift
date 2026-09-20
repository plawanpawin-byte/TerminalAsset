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
/// - `ext:<externalIdentifier>|<occurrence>` when the calendar provides an external identifier.
/// - `fp:<fingerprint>` otherwise (calendar + normalized title + start).
///
/// The occurrence is the original start as epoch seconds, except for all-day events: those float (they are "the
/// 15th", wherever the user is), and EventKit reports them as a different instant when the device time zone changes.
/// So an all-day occurrence is identified by its calendar day (`d2027-1-15`), which survives travel; otherwise the
/// context of a recurring all-day event would appear to vanish and a fresh empty record take its place.
///
/// `eventIdentifier` is deliberately NOT part of the key because EventKit may change it.
public enum EventIdentity {
    public static func key(
        for snapshot: CalendarEventSnapshot,
        disambiguator: String? = nil,
        calendar: Calendar = .current
    ) -> EventKey {
        let base: String
        if let external = normalized(snapshot.externalIdentifier), !external.isEmpty {
            base = "ext:\(external)|\(moment(snapshot.occurrenceDate, allDay: snapshot.isAllDay, calendar: calendar))"
        } else {
            base = "fp:\(fingerprint(for: snapshot, calendar: calendar))"
        }
        guard let disambiguator, !disambiguator.isEmpty else {
            return EventKey(rawValue: base)
        }
        return EventKey(rawValue: "\(base)|cal:\(disambiguator)")
    }

    /// Weak identity used only to re-link records whose key changed (for example the external identifier
    /// became available after the event was first seen).
    public static func fingerprint(for snapshot: CalendarEventSnapshot, calendar: Calendar = .current) -> String {
        let title = normalized(snapshot.title) ?? ""
        let start = moment(snapshot.startDate, allDay: snapshot.isAllDay, calendar: calendar)
        return "\(snapshot.calendarID)|\(title.lowercased())|\(start)"
    }

    private static func moment(_ date: Date, allDay: Bool, calendar: Calendar) -> String {
        guard allDay else { return String(epochSeconds(date)) }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "d\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded())
    }
}
