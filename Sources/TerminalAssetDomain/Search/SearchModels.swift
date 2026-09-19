import Foundation

public enum SearchScope: String, Sendable, CaseIterable, Identifiable {
    case all
    case events
    case tasks
    case notes
    case links
    case files

    public var id: String { rawValue }
}

public enum SearchDocumentKind: String, Sendable {
    case event
    case task
    case note
    case link
    case file
    case image
    case voice

    var scope: SearchScope {
        switch self {
        case .event: .events
        case .task: .tasks
        case .note, .voice: .notes
        case .link: .links
        case .file, .image: .files
        }
    }
}

/// One searchable thing, flattened from the database so ranking needs no persistence types.
/// Every document belongs to an event: an event document represents the event itself, the others its context.
public struct SearchDocument: Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: SearchDocumentKind
    public let title: String
    /// Note text, link address, file name or event location: everything searchable besides the title.
    public let body: String
    public let eventKey: EventKey
    public let eventTitle: String
    public let eventStart: Date
    public let eventEnd: Date
    public let eventIsAllDay: Bool
    public let createdAt: Date
    public let isDone: Bool

    public init(
        id: String,
        kind: SearchDocumentKind,
        title: String,
        body: String,
        eventKey: EventKey,
        eventTitle: String,
        eventStart: Date,
        eventEnd: Date,
        eventIsAllDay: Bool = false,
        createdAt: Date,
        isDone: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.eventKey = eventKey
        self.eventTitle = eventTitle
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.eventIsAllDay = eventIsAllDay
        self.createdAt = createdAt
        self.isDone = isDone
    }
}

public enum SearchSignalKind: String, Sendable {
    /// How the query matched (title, text, event name).
    case match
    /// How close the related event is in time.
    case temporal
    /// How recently the item was added.
    case recent
}

/// A human-readable reason a result ranked where it did.
public struct SearchSignal: Sendable, Hashable {
    public let kind: SearchSignalKind
    public let text: String

    public init(kind: SearchSignalKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
    public let document: SearchDocument
    public let score: Double
    public let snippet: String
    public let signals: [SearchSignal]

    public var id: String { document.id }

    public init(document: SearchDocument, score: Double, snippet: String, signals: [SearchSignal]) {
        self.document = document
        self.score = score
        self.snippet = snippet
        self.signals = signals
    }
}
