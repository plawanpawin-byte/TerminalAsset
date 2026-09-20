import Foundation

public enum SharedInboxError: Error, Sendable, Equatable {
    /// The App Group container is not available (missing entitlement or unsigned build).
    case containerUnavailable
    case payloadTooLarge(limitBytes: Int)
    case payloadMissing
    case writeFailed(reason: String)
    case readFailed(reason: String)
}

/// A shared item waiting in the queue.
public struct PendingInboxItem: Sendable, Equatable {
    public let manifest: InboxManifest
    /// Where the payload file currently is (inside the queue), if the item has one.
    public let payloadURL: URL?
}

/// File-based queue in the App Group container. The Share Extension writes, the app reads and clears.
///
/// Layout:
/// ```
/// <root>/Inbox/<uuid>/manifest.json (+ payload file)   queue
/// <root>/Inbox/.rejected/<uuid>/                       unreadable items set aside
/// <root>/Attachments/<uuid>/<file>                     payloads of items imported by the app
/// ```
/// An item directory is created under a hidden temp name and renamed into place only when complete, so the
/// app never sees a half-written item. The extension does no database work and no heavy processing.
public struct SharedInbox: Sendable {
    /// Share Extensions run with tight memory limits; large files are refused instead of risking a crash.
    public static let maxPayloadBytes = 100 * 1024 * 1024

    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func appGroup(_ identifier: String = AppGroup.identifier) throws -> SharedInbox {
        #if canImport(Darwin)
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SharedInboxError.containerUnavailable
        }
        return SharedInbox(rootURL: url)
        #else
        // App Groups exist only on Apple platforms; other platforms build the Domain module for tests.
        throw SharedInboxError.containerUnavailable
        #endif
    }

    // MARK: - Writing (Share Extension)

    /// Adds an item to the queue. `payload` is copied, never moved, so the caller's file is untouched.
    @discardableResult
    public func enqueue(_ draft: InboxDraft, payload: URL? = nil) throws -> InboxManifest {
        let fileManager = FileManager.default
        var draft = draft
        var payloadName: String?

        if let payload {
            let size = (try? payload.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= Self.maxPayloadBytes else {
                throw SharedInboxError.payloadTooLarge(limitBytes: Self.maxPayloadBytes)
            }
            payloadName = Self.sanitizedFileName(payload.lastPathComponent)
            draft.payloadFileName = payloadName
        } else if draft.kind == .image || draft.kind == .file {
            throw SharedInboxError.payloadMissing
        }

        let manifest = InboxManifest(id: UUID(), draft: draft)
        let staging = inboxDirectory.appendingPathComponent(".tmp-\(manifest.id.uuidString)", isDirectory: true)
        let destination = itemDirectory(for: manifest.id)

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            if let payload, let payloadName {
                try fileManager.copyItem(at: payload, to: staging.appendingPathComponent(payloadName))
            }
            let data = try Self.encoder.encode(manifest)
            try data.write(to: staging.appendingPathComponent(Self.manifestName), options: .atomic)
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw SharedInboxError.writeFailed(reason: error.localizedDescription)
        }
        return manifest
    }

    // MARK: - Reading (app)

    /// Complete items in the queue, oldest first. Unreadable items are moved aside and skipped.
    public func pending(now: Date = Date()) throws -> (items: [PendingInboxItem], rejected: Int) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inboxDirectory.path) else { return ([], 0) }
        removeStaleStaging(now: now)

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)
        } catch {
            throw SharedInboxError.readFailed(reason: error.localizedDescription)
        }

        var items: [PendingInboxItem] = []
        var rejected = 0
        for directory in children where !directory.lastPathComponent.hasPrefix(".") {
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent(Self.manifestName))
                let manifest = try Self.decoder.decode(InboxManifest.self, from: data)
                var payloadURL: URL?
                if let name = manifest.payloadFileName {
                    let url = directory.appendingPathComponent(name)
                    guard fileManager.fileExists(atPath: url.path) else {
                        throw SharedInboxError.payloadMissing
                    }
                    payloadURL = url
                }
                items.append(PendingInboxItem(manifest: manifest, payloadURL: payloadURL))
            } catch {
                setAside(directory)
                rejected += 1
            }
        }
        items.sort { $0.manifest.receivedAt < $1.manifest.receivedAt }
        return (items, rejected)
    }

    /// Copies the payload into permanent storage and returns its path relative to `attachmentsDirectory`.
    /// Copy, not move: the queue entry is removed only after the app has saved its database.
    public func storeAttachment(for item: PendingInboxItem) throws -> String? {
        guard let source = item.payloadURL, let name = item.manifest.payloadFileName else { return nil }
        let fileManager = FileManager.default
        let directory = attachmentsDirectory.appendingPathComponent(item.manifest.id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(name)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // The file only ever appears under its real name once it is complete: an app killed half-way through
            // leaves a `.part` file (ignored, replaced next time), never a truncated file the database points at.
            if !fileManager.fileExists(atPath: destination.path) {
                let partial = directory.appendingPathComponent(".\(name).part")
                try? fileManager.removeItem(at: partial)
                try fileManager.copyItem(at: source, to: partial)
                try fileManager.moveItem(at: partial, to: destination)
            }
        } catch {
            throw SharedInboxError.writeFailed(reason: error.localizedDescription)
        }
        return "\(item.manifest.id.uuidString)/\(name)"
    }

    /// Copies a file the user picked (from Files or Photos) into permanent storage and returns its path relative to
    /// `attachmentsDirectory`. The original is copied, never moved or changed. Refuses files over the size limit.
    public func importAttachment(from source: URL) throws -> String {
        let fileManager = FileManager.default
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.maxPayloadBytes else {
            throw SharedInboxError.payloadTooLarge(limitBytes: Self.maxPayloadBytes)
        }
        guard fileManager.fileExists(atPath: source.path) else { throw SharedInboxError.payloadMissing }

        let name = Self.sanitizedFileName(source.lastPathComponent)
        let folder = UUID().uuidString
        let directory = attachmentsDirectory.appendingPathComponent(folder, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: directory.appendingPathComponent(name))
        } catch {
            try? fileManager.removeItem(at: directory)
            throw SharedInboxError.writeFailed(reason: error.localizedDescription)
        }
        return "\(folder)/\(name)"
    }

    /// Removes an item from the queue once the app has safely stored it.
    public func remove(id: UUID) {
        try? FileManager.default.removeItem(at: itemDirectory(for: id))
    }

    public func attachmentURL(for relativePath: String) -> URL {
        attachmentsDirectory.appendingPathComponent(relativePath)
    }

    public func deleteAttachment(relativePath: String) {
        let url = attachmentURL(for: relativePath)
        try? FileManager.default.removeItem(at: url)
        // Drop the now-empty per-item directory as well.
        let parent = url.deletingLastPathComponent()
        if parent != attachmentsDirectory,
           (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    // MARK: - Storage

    /// Bytes used by imported attachments, for the "Storage" row in Settings.
    public func attachmentsSize() -> Int64 {
        Self.size(of: attachmentsDirectory)
    }

    /// Deletes every imported attachment and everything still waiting in the queue. Only used when the user
    /// chose "Delete all data"; nothing else in the app removes files in bulk.
    public func eraseAll() throws {
        let fileManager = FileManager.default
        for directory in [attachmentsDirectory, inboxDirectory] where fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                throw SharedInboxError.writeFailed(reason: error.localizedDescription)
            }
        }
    }

    private static func size(of directory: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    // MARK: - Layout

    public var inboxDirectory: URL { rootURL.appendingPathComponent("Inbox", isDirectory: true) }
    public var attachmentsDirectory: URL { rootURL.appendingPathComponent("Attachments", isDirectory: true) }

    private func itemDirectory(for id: UUID) -> URL {
        inboxDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// A share sheet killed mid-copy (memory limit) leaves its hidden `.tmp-*` folder behind. Nothing ever reads those,
    /// so ones older than an hour are removed rather than left to fill the container.
    private func removeStaleStaging(now: Date = Date()) {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: inboxDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for directory in children where directory.lastPathComponent.hasPrefix(".tmp-") {
            let modified = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > 3600 { try? fileManager.removeItem(at: directory) }
        }
    }

    private func setAside(_ directory: URL) {
        let fileManager = FileManager.default
        let rejectedRoot = inboxDirectory.appendingPathComponent(".rejected", isDirectory: true)
        try? fileManager.createDirectory(at: rejectedRoot, withIntermediateDirectories: true)
        let target = rejectedRoot.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
        try? fileManager.removeItem(at: target)
        try? fileManager.moveItem(at: directory, to: target)
    }

    static let manifestName = "manifest.json"

    static func sanitizedFileName(_ name: String) -> String {
        let last = URL(fileURLWithPath: name).lastPathComponent
        let cleaned = last
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == manifestName ? "file" : cleaned
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
