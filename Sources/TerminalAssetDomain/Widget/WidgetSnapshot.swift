import Foundation

/// What the home-screen widget needs, written by the app into the App Group and read by the widget extension.
///
/// The widget never opens the database or asks EventKit: it only reads this small file, so it starts fast, stays
/// within the extension's memory limit and works with no calendar permission prompt of its own.
public struct WidgetSnapshot: Sendable, Equatable, Codable {
    public static let fileName = "widget-snapshot.json"
    public static let defaultLimit = 6

    public struct Entry: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let location: String?
        public let openTasks: Int
        /// Whether anything at all is attached to the event.
        public let hasContext: Bool

        public init(
            id: String,
            title: String,
            start: Date,
            end: Date,
            location: String?,
            openTasks: Int,
            hasContext: Bool
        ) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.location = location
            self.openTasks = openTasks
            self.hasContext = hasContext
        }
    }

    public let generatedAt: Date
    /// Timed events that have not ended yet, soonest first.
    public let entries: [Entry]

    public init(generatedAt: Date, entries: [Entry]) {
        self.generatedAt = generatedAt
        self.entries = entries
    }

    /// The events still worth showing: timed, active and not yet finished, soonest first.
    public static func make(from events: [TimelineEvent], now: Date, limit: Int = defaultLimit) -> WidgetSnapshot {
        let entries = events
            .filter { $0.syncState == .active && !$0.isAllDay && $0.endDate > now }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
            .prefix(limit)
            .map { event in
                Entry(
                    id: event.key.rawValue,
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    location: event.location,
                    openTasks: event.summary.openTasks,
                    hasContext: !event.summary.isEmpty
                )
            }
        return WidgetSnapshot(generatedAt: now, entries: Array(entries))
    }

    // MARK: - Reading it at a given moment

    /// The event in progress at `date`, if any (the one that started most recently).
    public func current(at date: Date) -> Entry? {
        entries.filter { $0.start <= date && date < $0.end }.max { $0.start < $1.start }
    }

    /// Events that have not started yet at `date`, soonest first.
    public func upcoming(at date: Date) -> [Entry] {
        entries.filter { $0.start > date }
    }

    /// The moments after `date` at which what the widget shows changes: every start and end. The widget asks for a
    /// new timeline entry at each, so "Next: 3:00 PM" turns into "Now" on time without the app running.
    public func changeDates(after date: Date) -> [Date] {
        var dates = Set<Date>()
        for entry in entries {
            if entry.start > date { dates.insert(entry.start) }
            if entry.end > date { dates.insert(entry.end) }
        }
        return dates.sorted()
    }

    // MARK: - Coding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes atomically, so the widget never reads a half-written file.
    public func write(to directory: URL) throws {
        try encoded().write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// A missing or unreadable file means "nothing to show", never an error for the widget to surface.
    public static func read(from directory: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? decoded(from: data)
    }
}
