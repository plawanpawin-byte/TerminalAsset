#if canImport(SwiftData)
import Foundation
import SwiftData
import TerminalAssetDomain

extension ContextStore {
    /// Flattens events and their context into searchable documents. The ranking itself is `SearchEngine`.
    ///
    /// Every context item is included, including the context of events that have since disappeared from the
    /// calendar (their context is kept). An event's own document is included only while the event is active and
    /// within 60 days of `now`, which keeps the corpus small for people with years of recurring events.
    /// Scale note: this loads all events; when history grows large, replace it with an incremental index.
    public func searchCorpus(now: Date) throws -> [SearchDocument] {
        try perform {
            let horizon: TimeInterval = 60 * 86_400
            let events = try modelContext.fetch(FetchDescriptor<TemporalEvent>())
            var documents: [SearchDocument] = []

            for event in events {
                let key = EventKey(rawValue: event.eventKey)
                let isNear = event.endDate > now - horizon && event.startDate < now + horizon

                if event.syncState == .active, isNear {
                    documents.append(SearchDocument(
                        id: "event:\(event.eventKey)",
                        kind: .event,
                        title: event.title,
                        body: event.location ?? "",
                        eventKey: key,
                        eventTitle: event.title,
                        eventStart: event.startDate,
                        eventEnd: event.endDate,
                        createdAt: event.startDate
                    ))
                }

                for item in event.context?.items ?? [] {
                    documents.append(SearchDocument(
                        id: "item:\(item.id.uuidString)",
                        kind: SearchDocumentKind(rawValue: item.kindRaw) ?? .note,
                        title: item.title,
                        body: Self.searchBody(of: item),
                        eventKey: key,
                        eventTitle: event.title,
                        eventStart: event.startDate,
                        eventEnd: event.endDate,
                        createdAt: item.createdAt,
                        isDone: item.isDone
                    ))
                }
            }
            return documents
        }
    }

    private static func searchBody(of item: ContextItem) -> String {
        var parts: [String] = []
        if let detail = item.detail { parts.append(detail) }
        if let url = item.urlString { parts.append(url) }
        if let file = item.fileName { parts.append(URL(fileURLWithPath: file).lastPathComponent) }
        return parts.joined(separator: " ")
    }
}
#endif
