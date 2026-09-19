import Foundation

public struct CalendarDay: Sendable, Hashable, Identifiable {
    /// Start of the day.
    public let date: Date
    public let isInDisplayedMonth: Bool
    public let isToday: Bool

    public var id: Date { date }
}

/// Month layout for a calendar grid, honouring the user's first weekday.
public enum MonthGrid {
    public static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Rows of seven days covering the month: 4 to 6 rows, padded with days from the neighbouring months.
    public static func weeks(containing month: Date, calendar: Calendar, today: Date) -> [[CalendarDay]] {
        let first = startOfMonth(month, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let rows = (leading + dayCount + 6) / 7
        let todayStart = calendar.startOfDay(for: today)

        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        var weeks: [[CalendarDay]] = []
        for row in 0..<rows {
            var week: [CalendarDay] = []
            for column in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: row * 7 + column, to: gridStart) else { continue }
                week.append(CalendarDay(
                    date: date,
                    isInDisplayedMonth: calendar.isDate(date, equalTo: first, toGranularity: .month),
                    isToday: date == todayStart
                ))
            }
            weeks.append(week)
        }
        return weeks
    }

    /// Single-letter weekday headers starting from the calendar's first weekday.
    public static func weekdayHeaders(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    public static func month(byAdding months: Int, to date: Date, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .month, value: months, to: startOfMonth(date, calendar: calendar))
        return shifted ?? date
    }
}

/// Which events fall on which days.
public enum CalendarEvents {
    /// Number of active events touching each day (keyed by start of day). Multi-day events count on every day.
    public static func counts(for events: [TimelineEvent], calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for event in events where event.syncState == .active {
            let lastMoment = max(event.startDate, event.endDate.addingTimeInterval(-1))
            var day = calendar.startOfDay(for: event.startDate)
            let lastDay = calendar.startOfDay(for: lastMoment)
            var guardCount = 0
            while day <= lastDay, guardCount < 62 {
                counts[day, default: 0] += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
        }
        return counts
    }

    /// Active events touching `day`: all-day first, then by start time.
    public static func events(on day: Date, in events: [TimelineEvent], calendar: Calendar) -> [TimelineEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events
            .filter { event in
                guard event.syncState == .active else { return false }
                let eventEnd = max(event.endDate, event.startDate.addingTimeInterval(1))
                return event.startDate < end && eventEnd > start
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
    }
}

public struct PositionedEvent: Sendable, Hashable, Identifiable {
    public let event: TimelineEvent
    /// Minutes since midnight, clamped to the day.
    public let startMinute: Double
    public let endMinute: Double
    public let column: Int
    public let columnCount: Int

    public var id: EventKey { event.key }
}

/// Places a day's timed events on an hour grid, side by side when they overlap.
public enum DayLayout {
    public static func layout(
        events: [TimelineEvent],
        on day: Date,
        calendar: Calendar,
        minimumMinutes: Double = 30
    ) -> [PositionedEvent] {
        let dayStart = calendar.startOfDay(for: day)

        struct Item {
            let event: TimelineEvent
            let start: Double
            let end: Double
        }

        let items: [Item] = CalendarEvents.events(on: day, in: events, calendar: calendar)
            .filter { !$0.isAllDay }
            .map { event in
                let start = max(0, event.startDate.timeIntervalSince(dayStart) / 60)
                let rawEnd = min(1440, event.endDate.timeIntervalSince(dayStart) / 60)
                return Item(event: event, start: start, end: min(1440, max(rawEnd, start + minimumMinutes)))
            }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }

        var result: [PositionedEvent] = []
        var cluster: [(item: Item, column: Int)] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func flush() {
            let count = max(columnEnds.count, 1)
            for entry in cluster {
                result.append(PositionedEvent(
                    event: entry.item.event,
                    startMinute: entry.item.start,
                    endMinute: entry.item.end,
                    column: entry.column,
                    columnCount: count
                ))
            }
            cluster = []
            columnEnds = []
            clusterEnd = -Double.infinity
        }

        for item in items {
            if item.start >= clusterEnd { flush() }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(item.end) } else { columnEnds[column] = item.end }
            cluster.append((item, column))
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return result
    }
}
