import Foundation

public enum TimelinePhase: Sendable, Hashable {
    case past
    case current
    case upcoming
}

public struct TimelineEntry: Sendable, Hashable, Identifiable {
    public let event: TimelineEvent
    public let phase: TimelinePhase

    public var id: EventKey { event.key }
}

public enum HeroKind: Sendable, Hashable {
    /// An event is in progress.
    case now
    /// The next event later today.
    case upNext
    /// Nothing left today; the first event tomorrow.
    case tomorrow
}

/// The single event the Today screen puts first: "what am I about to do, and what do I need for it?"
public struct HeroEvent: Sendable, Hashable {
    public let entry: TimelineEntry
    public let kind: HeroKind
    /// 0...1 while the event is in progress, nil otherwise.
    public let progress: Double?
}

public struct DayStats: Sendable, Hashable {
    public let total: Int
    public let completed: Int
    public let remaining: Int
    /// Events overlapping today that no longer exist in the calendar. Their context is kept.
    public let missing: Int
}

public struct TodaySnapshot: Sendable, Equatable {
    public let hero: HeroEvent?
    public let allDay: [TimelineEntry]
    public let timeline: [TimelineEntry]
    public let stats: DayStats

    public var isEmpty: Bool { hero == nil && allDay.isEmpty && timeline.isEmpty }

    /// Unchecked tasks on today's events that have not finished yet. Tasks on past events are not counted:
    /// they no longer help the user get ready for anything.
    public var openTasks: Int {
        timeline.filter { $0.phase != .past }.reduce(0) { $0 + $1.event.summary.openTasks }
    }
}

/// Deterministic Today-screen logic. Pure: same events + same clock → same result.
public enum TodayTimeline {
    public static func build(events: [TimelineEvent], now: Date, calendar: Calendar) -> TodaySnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let startOfDayAfter = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow)
            ?? startOfTomorrow.addingTimeInterval(86_400)

        func overlapsToday(_ event: TimelineEvent) -> Bool {
            event.startDate < startOfTomorrow && event.endDate > startOfToday
        }

        let active = events.filter { $0.syncState == .active }
        let missingCount = events.filter { $0.syncState == .missing && overlapsToday($0) }.count

        let timedToday = active
            .filter { !$0.isAllDay && overlapsToday($0) }
            .sorted(by: byStart)
        let timeline = timedToday.map { TimelineEntry(event: $0, phase: phase(of: $0, at: now)) }

        let allDay = active
            .filter { $0.isAllDay && overlapsToday($0) }
            .sorted { $0.title < $1.title }
            .map { TimelineEntry(event: $0, phase: phase(of: $0, at: now)) }

        let hero = makeHero(
            timeline: timeline,
            active: active,
            now: now,
            startOfTomorrow: startOfTomorrow,
            startOfDayAfter: startOfDayAfter
        )

        let completed = timeline.filter { $0.phase == .past }.count
        let stats = DayStats(
            total: timeline.count,
            completed: completed,
            remaining: timeline.count - completed,
            missing: missingCount
        )
        return TodaySnapshot(hero: hero, allDay: allDay, timeline: timeline, stats: stats)
    }

    public static func progress(of event: TimelineEvent, at now: Date) -> Double {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard duration > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(event.startDate)
        return min(max(elapsed / duration, 0), 1)
    }

    // MARK: - Private

    private static func phase(of event: TimelineEvent, at now: Date) -> TimelinePhase {
        if now >= event.endDate { return .past }
        if now >= event.startDate { return .current }
        return .upcoming
    }

    private static func byStart(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        return lhs.title < rhs.title
    }

    private static func makeHero(
        timeline: [TimelineEntry],
        active: [TimelineEvent],
        now: Date,
        startOfTomorrow: Date,
        startOfDayAfter: Date
    ) -> HeroEvent? {
        if let current = timeline.last(where: { $0.phase == .current }) {
            return HeroEvent(entry: current, kind: .now, progress: progress(of: current.event, at: now))
        }
        let next = active
            .filter { !$0.isAllDay && $0.startDate > now && $0.startDate < startOfDayAfter }
            .min(by: byStart)
        guard let next else { return nil }
        let kind: HeroKind = next.startDate >= startOfTomorrow ? .tomorrow : .upNext
        return HeroEvent(entry: TimelineEntry(event: next, phase: .upcoming), kind: kind, progress: nil)
    }
}
