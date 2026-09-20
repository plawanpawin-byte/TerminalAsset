#if canImport(UserNotifications)
import Foundation
import TerminalAssetDomain

/// The wording of a prep reminder, in the user's language. The counts use plural rules from the string catalog.
enum ReminderText {
    static func title(for reminder: PrepReminder) -> String {
        String(localized: "\(reminder.eventTitle) · in \(reminder.minutesBefore) min")
    }

    static func body(for reminder: PrepReminder) -> String {
        switch reminder.preparation {
        case .nothingAttached:
            return String(localized: "Nothing attached yet. Add a note or a link while there is time.")
        case let .waiting(tasks, notes, links, files):
            var parts = [String(localized: "\(tasks) to do")]
            if notes > 0 { parts.append(String(localized: "\(notes) notes")) }
            if links > 0 { parts.append(String(localized: "\(links) links")) }
            if files > 0 { parts.append(String(localized: "\(files) files")) }
            return parts.joined(separator: " · ")
        }
    }
}
#endif
