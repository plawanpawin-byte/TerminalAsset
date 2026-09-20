import Foundation

/// One day of the calendar history feed: the events that start on `day`, ready to render as a section.
public struct HistoryDay: Sendable, Hashable, Identifiable {
    /// Start of the day, in the caller's calendar.
    public let day: Date
    public let events: [TimelineEvent]

    public var id: Date { day }

    public init(day: Date, events: [TimelineEvent]) {
        self.day = day
        self.events = events
    }
}

/// The calendar as a reverse-chronological feed: events grouped by the day they start, newest day first.
/// Pure: same events + same calendar → same result.
public enum CalendarHistory {
    /// Groups active events by start-of-day. Days are ordered newest first; within a day, all-day events come
    /// first and the rest sort by start time. Missing (soft-deleted) events are excluded — their day may vanish
    /// from the feed, but their context is never deleted.
    public static func days(from events: [TimelineEvent], calendar: Calendar) -> [HistoryDay] {
        let active = events.filter { $0.syncState == .active }
        let grouped = Dictionary(grouping: active) { calendar.startOfDay(for: $0.startDate) }
        return grouped
            .map { day, events in HistoryDay(day: day, events: events.sorted(by: order)) }
            .sorted { $0.day > $1.day }
    }

    private static func order(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.title < rhs.title
    }
}
