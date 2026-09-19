import Foundation

public enum ContextItemKind: String, Sendable, Codable, CaseIterable {
    case note
    case link
    case task
    case file
    case image
    case voice
}

/// Immutable copy of a persisted context item, safe to hand to the UI.
public struct ContextItemValue: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: ContextItemKind
    public let title: String
    public let detail: String?
    public let url: URL?
    public let isDone: Bool
    public let createdAt: Date
    /// Path of an attached file, relative to the shared attachments directory.
    public let fileName: String?

    public init(
        id: UUID,
        kind: ContextItemKind,
        title: String,
        detail: String?,
        url: URL?,
        isDone: Bool,
        createdAt: Date,
        fileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.url = url
        self.isDone = isDone
        self.createdAt = createdAt
        self.fileName = fileName
    }
}

/// Counts of what an event's context contains, used for badges and "is there anything to prepare" decisions.
public struct ContextSummary: Sendable, Hashable {
    public let notes: Int
    public let links: Int
    public let tasks: Int
    public let openTasks: Int
    /// Files, images and voice notes.
    public let attachments: Int

    public init(items: [ContextItemValue]) {
        var notes = 0, links = 0, tasks = 0, openTasks = 0, attachments = 0
        for item in items {
            switch item.kind {
            case .note: notes += 1
            case .link: links += 1
            case .task:
                tasks += 1
                if !item.isDone { openTasks += 1 }
            case .file, .image, .voice: attachments += 1
            }
        }
        self.notes = notes
        self.links = links
        self.tasks = tasks
        self.openTasks = openTasks
        self.attachments = attachments
    }

    public var total: Int { notes + links + tasks + attachments }
    public var isEmpty: Bool { total == 0 }
}

public enum ContextValidationError: Error, Sendable, Equatable {
    case emptyTitle
    case titleTooLong
    case invalidURL
    case missingFile
    case unsupportedKind
}

/// Raw user input for a new context item.
public struct ContextItemDraft: Sendable, Equatable {
    public static let maxTitleLength = 200

    public var kind: ContextItemKind
    public var title: String
    public var detail: String
    public var urlString: String
    /// Path of an already-stored attachment (for `.file` and `.image`).
    public var fileName: String

    public init(
        kind: ContextItemKind,
        title: String = "",
        detail: String = "",
        urlString: String = "",
        fileName: String = ""
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.urlString = urlString
        self.fileName = fileName
    }

    /// Trims and normalizes the input. Links get an `https://` scheme when missing and default their title to the host.
    public func validated() throws -> ValidatedContextItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = trimmedDetail.isEmpty ? nil : trimmedDetail

        switch kind {
        case .note, .task:
            guard !trimmedTitle.isEmpty else { throw ContextValidationError.emptyTitle }
            guard trimmedTitle.count <= Self.maxTitleLength else { throw ContextValidationError.titleTooLong }
            return ValidatedContextItem(kind: kind, title: trimmedTitle, detail: normalizedDetail, url: nil, fileName: nil)

        case .link:
            let url = try Self.normalizedURL(from: urlString)
            let host = url.host(percentEncoded: false) ?? url.absoluteString
            let resolvedTitle = trimmedTitle.isEmpty ? host : trimmedTitle
            guard resolvedTitle.count <= Self.maxTitleLength else { throw ContextValidationError.titleTooLong }
            return ValidatedContextItem(kind: kind, title: resolvedTitle, detail: normalizedDetail, url: url, fileName: nil)

        case .file, .image:
            let path = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { throw ContextValidationError.missingFile }
            let resolvedTitle = trimmedTitle.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmedTitle
            guard resolvedTitle.count <= Self.maxTitleLength else { throw ContextValidationError.titleTooLong }
            return ValidatedContextItem(kind: kind, title: resolvedTitle, detail: normalizedDetail, url: nil, fileName: path)

        case .voice:
            throw ContextValidationError.unsupportedKind
        }
    }

    private static func normalizedURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContextValidationError.invalidURL }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false),
              !host.isEmpty
        else { throw ContextValidationError.invalidURL }
        return url
    }
}

public struct ValidatedContextItem: Sendable, Equatable {
    public let kind: ContextItemKind
    public let title: String
    public let detail: String?
    public let url: URL?
    public let fileName: String?
}

public enum ContextStoreError: Error, Sendable, Equatable {
    case eventNotFound
    case itemNotFound
    case notATask
    case invalidItem(ContextValidationError)
    case persistence(reason: String)
}
