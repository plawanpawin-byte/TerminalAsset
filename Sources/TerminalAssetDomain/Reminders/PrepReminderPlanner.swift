import Foundation

/// One notification to schedule: "ISO Audit Preparation · in 15 min", with what is waiting for the user.
public struct PrepReminder: Sendable, Equatable, Identifiable {
    /// Stable per event occurrence, so replanning replaces a reminder instead of adding a second one.
    public let id: String
    public let eventKey: EventKey
    public let fireDate: Date
    public let title: String
    public let body: String
}

/// Decides which prep reminders should exist for the coming events. Pure and deterministic: same events and
/// clock in, same reminders out, so it is fully testable without notifications, a device or a network.
///
/// A reminder is only worth interrupting for when the event has something to prepare (open tasks) or nothing at
/// all attached to a meeting-sized event. A quiet event with notes or links already attached gets no reminder.
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
            title: title(for: event, fire: fire),
            body: body(for: summary)
        )
    }

    private static func title(for event: TimelineEvent, fire: Date) -> String {
        let minutes = max(1, Int((event.startDate.timeIntervalSince(fire) / 60).rounded()))
        return "\(event.title) · in \(minutes) min"
    }

    private static func body(for summary: ContextSummary) -> String {
        guard !summary.isEmpty else { return "Nothing attached yet. Add a note or a link while there is time." }

        var parts: [String] = []
        parts.append("\(summary.openTasks) task\(summary.openTasks == 1 ? "" : "s") to do")
        if summary.notes > 0 { parts.append("\(summary.notes) note\(summary.notes == 1 ? "" : "s")") }
        if summary.links > 0 { parts.append("\(summary.links) link\(summary.links == 1 ? "" : "s")") }
        if summary.attachments > 0 { parts.append("\(summary.attachments) file\(summary.attachments == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
