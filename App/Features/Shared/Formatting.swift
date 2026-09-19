import Foundation
import TerminalAssetDomain

/// Presentation-only text helpers. No business rules live here.
enum TimeText {
    /// "9:00 – 10:00 AM"
    static func range(of event: TimelineEvent) -> String {
        if event.isAllDay { return "All day" }
        let interval = event.startDate..<max(event.startDate, event.endDate)
        return interval.formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened))
    }

    /// "in 25 minutes" / "5 minutes ago"
    static func relative(_ date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "35 min left"; rounds up so an event with seconds left never reads "0 min left".
    static func remaining(until end: Date, from now: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(now))
        let roundedUp = (seconds / 60).rounded(.up) * 60
        let text = Duration.seconds(roundedUp)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(text) left"
    }
}

extension ContextSummary {
    var accessibilityDescription: String {
        var parts: [String] = []
        if tasks > 0 { parts.append("\(openTasks) of \(tasks) tasks open") }
        if notes > 0 { parts.append("\(notes) \(notes == 1 ? "note" : "notes")") }
        if links > 0 { parts.append("\(links) \(links == 1 ? "link" : "links")") }
        if attachments > 0 { parts.append("\(attachments) \(attachments == 1 ? "attachment" : "attachments")") }
        return parts.joined(separator: ", ")
    }
}
