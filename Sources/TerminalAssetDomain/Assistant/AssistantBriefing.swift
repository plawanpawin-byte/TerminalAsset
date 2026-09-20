import Foundation

/// A deterministic "what needs your attention" summary of the calendar, computed with no AI: the next
/// event to prepare for, and past events that still have open tasks. This is the Assistant's local-first
/// brain; generative ranking/summaries can layer on top later behind the Context Engine.
public struct AssistantBriefing: Sendable, Hashable {
    /// The soonest timed event that has not ended yet (ongoing counts). All-day events are excluded because
    /// they have no meaningful "up next" moment. `nil` when nothing is ongoing or ahead.
    public let upNext: TimelineEvent?

    /// Past events (already ended) that still carry open tasks, most recently ended first.
    public let looseEnds: [TimelineEvent]

    public init(upNext: TimelineEvent?, looseEnds: [TimelineEvent]) {
        self.upNext = upNext
        self.looseEnds = looseEnds
    }

    public var isEmpty: Bool { upNext == nil && looseEnds.isEmpty }

    public static func make(
        from events: [TimelineEvent],
        now: Date,
        maxLooseEnds: Int = 5
    ) -> AssistantBriefing {
        let active = events.filter { $0.syncState == .active }

        let upNext = active
            .filter { !$0.isAllDay && $0.endDate > now }
            .min { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }

        let looseEnds = active
            .filter { $0.endDate <= now && $0.summary.openTasks > 0 }
            .sorted { lhs, rhs in
                if lhs.endDate != rhs.endDate { return lhs.endDate > rhs.endDate }
                return lhs.title < rhs.title
            }
            .prefix(maxLooseEnds)

        return AssistantBriefing(upNext: upNext, looseEnds: Array(looseEnds))
    }
}
