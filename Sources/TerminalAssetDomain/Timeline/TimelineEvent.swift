import Foundation

/// An event as the UI sees it: calendar fields plus the context attached to it.
public struct TimelineEvent: Sendable, Hashable, Identifiable {
    public let key: EventKey
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?
    public let syncState: SyncState
    public let items: [ContextItemValue]

    public init(
        key: EventKey,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        syncState: SyncState,
        items: [ContextItemValue]
    ) {
        self.key = key
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.syncState = syncState
        self.items = items
    }

    public var id: EventKey { key }
    public var summary: ContextSummary { ContextSummary(items: items) }
    public var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
}
