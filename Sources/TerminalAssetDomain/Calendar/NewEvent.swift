import Foundation

/// A calendar the user can add events to.
public struct CalendarInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// The calendar the system uses for new events unless the user picks another one.
    public let isDefault: Bool

    public init(id: String, title: String, isDefault: Bool) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

public enum EventDraftError: Error, Sendable, Equatable {
    case emptyTitle
    case titleTooLong
    case locationTooLong
    case endNotAfterStart
}

/// Raw user input for a new calendar event.
public struct NewEventDraft: Sendable, Equatable {
    public static let maxTitleLength = 200
    public static let maxLocationLength = 200
    public static let defaultDuration: TimeInterval = 3600

    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String
    /// `nil` means "the system default calendar".
    public var calendarID: String?

    public init(
        title: String = "",
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String = "",
        calendarID: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendarID = calendarID
    }

    /// A sensible starting point for the form: the next full hour when adding to today (or 23:00 if that would
    /// spill into tomorrow), 09:00 for any other day. One hour long.
    public static func starting(on day: Date, now: Date, calendar: Calendar) -> NewEventDraft {
        let start: Date
        if calendar.isDate(day, inSameDayAs: now) {
            let nextHour = calendar.nextDate(
                after: now,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            )
            if let nextHour, calendar.isDate(nextHour, inSameDayAs: day) {
                start = nextHour
            } else {
                start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day) ?? day
            }
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        return NewEventDraft(start: start, end: start.addingTimeInterval(defaultDuration))
    }

    /// Moves the start and drags the end along, so changing the start never silently shortens or inverts the event.
    public mutating func moveStart(to newStart: Date) {
        let duration = max(0, end.timeIntervalSince(start))
        start = newStart
        end = newStart.addingTimeInterval(duration)
    }

    /// Trims and checks the input. All-day events are snapped to whole days; the end is the last day (inclusive).
    public func validated(calendar: Calendar) throws -> ValidatedNewEvent {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw EventDraftError.emptyTitle }
        guard trimmedTitle.count <= Self.maxTitleLength else { throw EventDraftError.titleTooLong }

        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLocation.count <= Self.maxLocationLength else { throw EventDraftError.locationTooLong }

        let resolvedStart: Date
        let resolvedEnd: Date
        if isAllDay {
            resolvedStart = calendar.startOfDay(for: start)
            resolvedEnd = calendar.startOfDay(for: end)
            guard resolvedEnd >= resolvedStart else { throw EventDraftError.endNotAfterStart }
        } else {
            resolvedStart = start
            resolvedEnd = end
            guard resolvedEnd > resolvedStart else { throw EventDraftError.endNotAfterStart }
        }

        return ValidatedNewEvent(
            title: trimmedTitle,
            start: resolvedStart,
            end: resolvedEnd,
            isAllDay: isAllDay,
            location: trimmedLocation.isEmpty ? nil : trimmedLocation,
            calendarID: calendarID
        )
    }
}

/// A draft that passed validation. Only this shape is handed to a `CalendarRepository`.
public struct ValidatedNewEvent: Sendable, Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let calendarID: String?
}
