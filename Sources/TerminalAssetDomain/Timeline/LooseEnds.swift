import Foundation

/// Events from earlier days that still have open tasks: things left behind that the user may want to close.
/// Deterministic and pure, like the rest of Today's logic.
///
/// Today's own events are left out on purpose: they are already in the day's schedule with their task counts, so
/// listing them twice would only repeat what is on screen.
public enum LooseEnds {
    public static let defaultLimit = 5

    /// Ended before today began and still carrying open tasks; most recently ended first.
    public static func make(
        from events: [TimelineEvent],
        now: Date,
        calendar: Calendar,
        limit: Int = defaultLimit
    ) -> [TimelineEvent] {
        let startOfToday = calendar.startOfDay(for: now)
        return Array(
            events
                .filter { $0.syncState == .active && $0.endDate <= startOfToday && $0.summary.openTasks > 0 }
                .sorted { lhs, rhs in
                    if lhs.endDate != rhs.endDate { return lhs.endDate > rhs.endDate }
                    return lhs.title < rhs.title
                }
                .prefix(limit)
        )
    }
}
