import Foundation
import TerminalAssetDomain

/// Presentation-only text helpers. No business rules live here.
enum TimeText {
    /// "9:00 – 10:00 AM"
    static func range(of event: TimelineEvent) -> String {
        if event.isAllDay { return String(localized: "All day") }
        let interval = event.startDate..<max(event.startDate, event.endDate)
        return interval.formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened))
    }

    /// "Today, 4:20 PM", "Tomorrow · All day" or "Sep 19, 4:20 PM": short enough to sit on one line in a list row.
    static func compact(start: Date, isAllDay: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let daysAway = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)
        ).day
        let day = switch daysAway ?? Int.max {
        case 0: String(localized: "Today")
        case 1: String(localized: "Tomorrow")
        case -1: String(localized: "Yesterday")
        default: start.formatted(.dateTime.month(.abbreviated).day())
        }
        if isAllDay { return String(localized: "\(day) · All day") }
        return "\(day), \(start.formatted(date: .omitted, time: .shortened))"
    }

    /// "in 25 minutes" / "5 minutes ago"
    static func relative(_ date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "in 1h 30m"; rounds up so it never reads "in 0m", and says "Starting now" inside the last minute.
    static func countdown(to start: Date, from now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 60 else { return String(localized: "Starting now") }
        let roundedUp = (seconds / 60).rounded(.up) * 60
        let text = Duration.seconds(roundedUp)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return String(localized: "in \(text)")
    }

    /// "35 min left"; rounds up so an event with seconds left never reads "0 min left".
    static func remaining(until end: Date, from now: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(now))
        let roundedUp = (seconds / 60).rounded(.up) * 60
        let text = Duration.seconds(roundedUp)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "\(text) left")
    }
}

extension ContextSummary {
    var accessibilityDescription: String {
        var parts: [String] = []
        if tasks > 0 { parts.append(String(localized: "Open tasks: \(openTasks) of \(tasks)")) }
        if notes > 0 { parts.append(String(localized: "\(notes) notes")) }
        if links > 0 { parts.append(String(localized: "\(links) links")) }
        if attachments > 0 { parts.append(String(localized: "\(attachments) attachments")) }
        return parts.joined(separator: ", ")
    }
}
