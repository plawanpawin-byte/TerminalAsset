import Foundation

/// Everything TerminalAsset stores about the user, as a plain JSON document they can keep or move elsewhere.
///
/// Calendar events themselves belong to the calendar, so they appear here only as the titles and times the
/// context hangs from. Attached files are listed by name but not embedded: they stay in the app's storage.
public struct DataExport: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public struct Event: Sendable, Equatable, Codable {
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
        public let location: String?
        /// `active`, or `missing` when the event is no longer in the calendar (its context is kept).
        public let state: String
        public let items: [Item]
    }

    public struct Item: Sendable, Equatable, Codable {
        /// `note`, `link`, `task`, `file`, `image` or `voice`.
        public let kind: String
        public let title: String
        public let detail: String?
        public let url: String?
        public let done: Bool?
        public let added: Date
        public let attachedFile: String?
    }

    public let version: Int
    public let generatedAt: Date
    public let note: String
    public let events: [Event]

    /// Only events that carry context are exported: an event with nothing attached has nothing of the user's in it.
    public static func make(from events: [TimelineEvent], generatedAt: Date) -> DataExport {
        let exported = events
            .filter { !$0.items.isEmpty }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Event(
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    state: event.syncState.rawValue,
                    items: event.items.map(item(from:))
                )
            }
        return DataExport(
            version: currentVersion,
            generatedAt: generatedAt,
            note: "Notes, links, tasks and file names attached to your calendar events. Attached files are not included in this document.",
            events: exported
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// "TerminalAsset-2027-01-15.json"
    public static func fileName(for date: Date, calendar: Calendar) -> String {
        // The user's day, in the Gregorian calendar: on a Buddhist-calendar device the year would otherwise read 2570.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return "TerminalAsset-\(String(format: "%04d-%02d-%02d", year, month, day)).json"
    }

    private static func item(from value: ContextItemValue) -> Item {
        Item(
            kind: value.kind.rawValue,
            title: value.title,
            detail: value.detail,
            url: value.url?.absoluteString,
            done: value.kind == .task ? value.isDone : nil,
            added: value.createdAt,
            attachedFile: value.fileName
        )
    }
}
