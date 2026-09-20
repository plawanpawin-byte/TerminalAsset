import Foundation

/// Identifier of the App Group shared by the app and the Share Extension.
public enum AppGroup {
    public static let identifier = "group.com.terminalasset.app"
}

public enum InboxPayloadKind: String, Sendable, Codable, CaseIterable {
    case url
    case text
    case image
    case file
}

/// What the user asked for in the Share Extension. Resolved against the calendar at the time of sharing.
public enum ShareIntent: String, Sendable, Codable, CaseIterable {
    /// Let TerminalAsset suggest an event; the user confirms in the Inbox.
    case decide
    case currentEvent
    case upcomingEvent
}

/// What the Share Extension knows when it enqueues an item. No calendar access, no database.
public struct InboxDraft: Sendable, Equatable {
    public var kind: InboxPayloadKind
    public var title: String
    public var text: String?
    public var urlString: String?
    /// File name of the payload copied next to the manifest (for `.image` and `.file`).
    public var payloadFileName: String?
    public var intent: ShareIntent
    public var receivedAt: Date

    public init(
        kind: InboxPayloadKind,
        title: String,
        text: String? = nil,
        urlString: String? = nil,
        payloadFileName: String? = nil,
        intent: ShareIntent = .decide,
        receivedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.urlString = urlString
        self.payloadFileName = payloadFileName
        self.intent = intent
        self.receivedAt = receivedAt
    }
}

/// The JSON record written next to a shared payload.
public struct InboxManifest: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: InboxPayloadKind
    public let title: String
    public let text: String?
    public let urlString: String?
    public let payloadFileName: String?
    public let intent: ShareIntent
    public let receivedAt: Date

    public init(id: UUID, draft: InboxDraft) {
        self.id = id
        self.kind = draft.kind
        self.title = draft.title
        self.text = draft.text
        self.urlString = draft.urlString
        self.payloadFileName = draft.payloadFileName
        self.intent = draft.intent
        self.receivedAt = draft.receivedAt
    }

    /// Text used to match this item against events.
    public var searchableText: String {
        [title, text, urlString].compactMap { $0 }.joined(separator: " ")
    }

    /// The context item this share becomes when attached to an event.
    public func contextDraft(attachmentPath: String?) -> ContextItemDraft {
        switch kind {
        case .url:
            return ContextItemDraft(kind: .link, title: title, urlString: urlString ?? "")
        case .text:
            let body = (text ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
            let noteTitle = firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
            return ContextItemDraft(
                kind: .note,
                title: noteTitle.isEmpty ? "Shared text" : noteTitle,
                detail: body == noteTitle ? "" : body
            )
        case .image:
            return ContextItemDraft(kind: .image, title: title, fileName: attachmentPath ?? "")
        case .file:
            return ContextItemDraft(kind: .file, title: title, fileName: attachmentPath ?? "")
        }
    }

    /// What to show under the title in the Inbox, as facts the app can word.
    public var subtitle: InboxSubtitle {
        switch kind {
        case .url:
            if let host = urlString.flatMap({ URL(string: $0)?.host(percentEncoded: false) }) { return .host(host) }
            return .link
        case .text:
            let body = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // The title is already the start of the text; repeating it under itself adds nothing.
            return body.isEmpty || body == title || body.hasPrefix(title) ? .text : .excerpt(String(body.prefix(80)))
        case .image:
            return .image
        case .file:
            let ext = payloadFileName.map { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? ""
            return ext.isEmpty ? .file : .fileType(ext)
        }
    }
}

/// The line under an Inbox item's title.
public enum InboxSubtitle: Sendable, Hashable {
    /// A web link; the site it points to.
    case host(String)
    case link
    /// Text whose title already says it all.
    case text
    /// The start of a longer text.
    case excerpt(String)
    case image
    /// A file with a known extension, upper-cased ("XLSX").
    case fileType(String)
    case file
}

/// A shared item as the Inbox screen sees it.
public struct InboxItemValue: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: InboxPayloadKind
    public let title: String
    public let subtitle: InboxSubtitle
    public let receivedAt: Date
    public let suggestion: EventSuggestion?

    public init(
        id: UUID,
        kind: InboxPayloadKind,
        title: String,
        subtitle: InboxSubtitle,
        receivedAt: Date,
        suggestion: EventSuggestion?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.receivedAt = receivedAt
        self.suggestion = suggestion
    }
}

public struct AutoAttachment: Sendable, Equatable {
    public let title: String
    public let eventTitle: String

    public init(title: String, eventTitle: String) {
        self.title = title
        self.eventTitle = eventTitle
    }
}

public struct IngestReport: Sendable, Equatable {
    public let imported: Int
    public let autoAttached: [AutoAttachment]
    /// Shared items that could not be read and were set aside.
    public let rejected: Int

    public init(imported: Int, autoAttached: [AutoAttachment], rejected: Int) {
        self.imported = imported
        self.autoAttached = autoAttached
        self.rejected = rejected
    }
}
