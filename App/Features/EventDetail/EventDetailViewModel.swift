import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class EventDetailViewModel {
    private(set) var event: TimelineEvent?
    private(set) var isLoading = true
    var errorMessage: String?

    let key: EventKey

    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let attachments: SharedInbox?
    @ObservationIgnored private let onChange: @MainActor () async -> Void

    init(
        key: EventKey,
        store: ContextStore,
        attachments: SharedInbox? = nil,
        onChange: @escaping @MainActor () async -> Void
    ) {
        self.key = key
        self.store = store
        self.attachments = attachments
        self.onChange = onChange
    }

    /// Where an attached file lives now, or nil (with a message) when it is gone. Files stay where the app stored
    /// them; this only looks, it never moves or deletes anything.
    func attachmentURL(for item: ContextItemValue) -> URL? {
        guard let attachments, let path = item.fileName else {
            errorMessage = String(localized: "The file for this item is missing.")
            return nil
        }
        let url = attachments.attachmentURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = String(localized: "The file for this item is missing.")
            return nil
        }
        return url
    }

    func load() async {
        do {
            event = try await store.event(forKey: key)
        } catch {
            errorMessage = TodayViewModel.message(for: error)
        }
        isLoading = false
    }

    /// Returns a user-facing message when the item could not be saved, nil on success.
    func add(_ draft: ContextItemDraft) async -> String? {
        do {
            try await store.addItem(to: key, draft: draft, now: .now)
            await load()
            await onChange()
            return nil
        } catch ContextStoreError.invalidItem(let validation) {
            return validation.userMessage
        } catch {
            return TodayViewModel.message(for: error)
        }
    }

    /// Copies a file the user picked into the app's own storage and attaches it to the event. The original stays where
    /// it was. Returns a user-facing message when it could not be attached, nil on success.
    func addAttachment(from url: URL, isImage: Bool) async -> String? {
        guard let attachments else {
            return String(localized: "Files can't be attached on this device yet.")
        }
        // Files from the Files app are only readable while this access is open.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let path: String
        do {
            path = try await Task.detached(priority: .userInitiated) {
                try attachments.importAttachment(from: url)
            }.value
        } catch SharedInboxError.payloadTooLarge(let limit) {
            return String(localized: "That file is too large to attach (limit \(limit / 1_048_576) MB).")
        } catch {
            return String(localized: "Couldn't attach that file. Please try again.")
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let draft = ContextItemDraft(kind: isImage ? .image : .file, title: name, fileName: path)
        if let message = await add(draft) {
            // The copy has no record pointing at it, so it must not be left behind.
            attachments.deleteAttachment(relativePath: path)
            return message
        }
        return nil
    }

    /// Attaches a photo picked in the system photo picker (which needs no photo-library permission).
    func addPhoto(data: Data, fileExtension: String) async -> String? {
        // Colons in the timestamp become underscores when the file is stored.
        let name = "\(String(localized: "Photo")) \(Date.now.formatted(.iso8601)).\(fileExtension)"
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try await Task.detached(priority: .userInitiated) {
                try data.write(to: temporary, options: .atomic)
            }.value
        } catch {
            return String(localized: "Couldn't attach that file. Please try again.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        return await addAttachment(from: temporary, isImage: true)
    }

    /// Returns a user-facing message when the change could not be saved, nil on success.
    func update(_ id: UUID, with draft: ContextItemDraft) async -> String? {
        do {
            try await store.updateItem(id: id, with: draft)
            await load()
            await onChange()
            return nil
        } catch ContextStoreError.invalidItem(let validation) {
            return validation.userMessage
        } catch {
            return TodayViewModel.message(for: error)
        }
    }

    func setTask(_ id: UUID, done: Bool) async {
        await mutate { try await self.store.setTaskDone(id: id, isDone: done) }
    }

    func delete(_ id: UUID) async {
        await mutate {
            // The stored copy of an attached file goes with its item, unless an Inbox entry still needs it for undo.
            if let path = try await self.store.deleteItem(id: id) {
                self.attachments?.deleteAttachment(relativePath: path)
            }
        }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
            await onChange()
        } catch {
            errorMessage = TodayViewModel.message(for: error)
        }
    }
}

extension ContextValidationError {
    var userMessage: String {
        switch self {
        case .emptyTitle: String(localized: "Enter a title.")
        case .titleTooLong: String(localized: "That title is too long. Keep it under \(ContextItemDraft.maxTitleLength) characters.")
        case .invalidURL: String(localized: "Enter a valid web address, like example.com.")
        case .missingFile: String(localized: "The file for this item is missing.")
        case .unsupportedKind: String(localized: "That kind of item can't be added here yet.")
        }
    }
}
