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
    @ObservationIgnored private let onChange: @MainActor () async -> Void

    init(key: EventKey, store: ContextStore, onChange: @escaping @MainActor () async -> Void) {
        self.key = key
        self.store = store
        self.onChange = onChange
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

    func setTask(_ id: UUID, done: Bool) async {
        await mutate { try await self.store.setTaskDone(id: id, isDone: done) }
    }

    func delete(_ id: UUID) async {
        await mutate { try await self.store.deleteItem(id: id) }
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
        case .emptyTitle: "Enter a title."
        case .titleTooLong: "That title is too long. Keep it under \(ContextItemDraft.maxTitleLength) characters."
        case .invalidURL: "Enter a valid web address, like example.com."
        case .unsupportedKind: "That kind of item can't be added here yet."
        }
    }
}
