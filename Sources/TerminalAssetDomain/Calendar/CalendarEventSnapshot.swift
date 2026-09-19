import Foundation

/// Immutable, `Sendable` copy of the calendar fields TerminalAsset cares about.
///
/// This is the only shape in which EventKit data crosses out of the calendar layer, so nothing above
/// `CalendarRepository` ever touches an `EKEvent`.
public struct CalendarEventSnapshot: Sendable, Hashable {
    /// `EKEvent.eventIdentifier`. Volatile: shared by every occurrence of a recurring series and may change on edits.
    public let eventIdentifier: String?
    /// `EKEvent.calendarItemExternalIdentifier`. Server-side identifier; nil for some local calendars.
    public let externalIdentifier: String?
    public let calendarID: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    /// The occurrence's ORIGINAL start date. Unlike `startDate` it does not change when a single occurrence is moved.
    public let occurrenceDate: Date
    public let isAllDay: Bool
    public let location: String?
    /// True for series members and detached (individually modified) occurrences.
    public let isRecurring: Bool

    public init(
        eventIdentifier: String?,
        externalIdentifier: String?,
        calendarID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        occurrenceDate: Date,
        isAllDay: Bool,
        location: String?,
        isRecurring: Bool
    ) {
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.occurrenceDate = occurrenceDate
        self.isAllDay = isAllDay
        self.location = location
        self.isRecurring = isRecurring
    }
}
