import Foundation

/// One notification to schedule: what the event is, how soon it starts, and what is waiting for the user. It holds
/// facts, not wording, so the notification can be phrased in the user's language where it is scheduled.
public struct PrepReminder: Sendable, Equatable, Identifiable {
    public enum Preparation: Sendable, Equatable {
        /// The event has nothing attached at all.
        case nothingAttached
        /// The event has open tasks (and maybe other context).
        case waiting(tasks: Int, notes: Int, links: Int, files: Int)
    }

    /// Stable per event occurrence, so replanning replaces a reminder instead of adding a second one.
    public let id: String
    public let eventKey: EventKey
    public let fireDate: Date
    public let eventTitle: String
    /// Whole minutes between the reminder and the start of the event (at least 1).
    public let minutesBefore: Int
    public let preparation: Preparation
}

/// Decides which prep reminders should exist for the coming events. Pure and deterministic: same events and
/// clock in, same reminders out, so it is fully testable without notifications, a device or a network.
///
/// A reminder is only worth interrupting for when the event has something to prepare (open tasks) or nothing
/// at all attached (a nudge to add some). A quiet event with notes or links already attached gets no reminder.
/// The user opts in to reminders and the count is capped (`limit`), so this is the whole filter: no event kind or
/// length is guessed at.
public enum PrepReminderPlanner {
    public struct Settings: Sendable, Equatable {
        /// How long before the event the reminder fires.
        public var leadTime: TimeInterval
        /// How far ahead reminders are planned. iOS keeps at most 64 pending notifications per app.
        public var horizon: TimeInterval
        public var limit: Int

        public init(leadTime: TimeInterval = 15 * 60, horizon: TimeInterval = 48 * 3600, limit: Int = 20) {
            self.leadTime = leadTime
            self.horizon = horizon
            self.limit = limit
        }
    }

    public static let idPrefix = "prep."

    public static func plan(from events: [TimelineEvent], now: Date, settings: Settings = Settings()) -> [PrepReminder] {
        let reminders = events
            .filter { $0.syncState == .active && !$0.isAllDay }
            .compactMap { reminder(for: $0, now: now, settings: settings) }
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.id < rhs.id
            }
        return Array(reminders.prefix(settings.limit))
    }

    // MARK: - Private

    private static func reminder(for event: TimelineEvent, now: Date, settings: Settings) -> PrepReminder? {
        guard event.startDate > now, event.startDate <= now.addingTimeInterval(settings.horizon) else { return nil }
        let summary = event.summary
        guard summary.openTasks > 0 || summary.isEmpty else { return nil }

        // If the lead time has already passed, remind shortly from now rather than skipping an imminent event.
        let ideal = event.startDate.addingTimeInterval(-settings.leadTime)
        let fire = max(ideal, now.addingTimeInterval(60))
        guard fire < event.startDate else { return nil }

        return PrepReminder(
            id: idPrefix + event.key.rawValue,
            eventKey: event.key,
            fireDate: fire,
            eventTitle: event.title,
            minutesBefore: max(1, Int((event.startDate.timeIntervalSince(fire) / 60).rounded())),
            preparation: summary.isEmpty
                ? .nothingAttached
                : .waiting(
                    tasks: summary.openTasks, notes: summary.notes,
                    links: summary.links, files: summary.attachments
                )
        )
    }
}
