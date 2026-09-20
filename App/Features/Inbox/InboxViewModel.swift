import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class InboxViewModel {
    /// Transient message at the bottom of the Inbox. `undoTarget` is set when the action can be reversed.
    struct Banner: Identifiable {
        let id = UUID()
        let message: String
        let undoTarget: UUID?
    }

    private(set) var items: [InboxItemValue] = []
    private(set) var banner: Banner?
    private(set) var problem: String?
    private(set) var choices: [TimelineEvent] = []

    /// False when the App Group container is unavailable (for example an unsigned build): the rest of the app
    /// keeps working, but nothing can be shared in.
    let sharingAvailable: Bool

    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let shared: SharedInbox?
    @ObservationIgnored private let onContextChanged: @MainActor () async -> Void

    init(
        store: ContextStore,
        shared: SharedInbox?,
        onContextChanged: @escaping @MainActor () async -> Void
    ) {
        self.store = store
        self.shared = shared
        self.sharingAvailable = shared != nil
        self.onContextChanged = onContextChanged
    }

    /// Imports anything queued by the Share Extension, then reloads the waiting list.
    func refresh() async {
        do {
            if let shared {
                let report = try await store.ingest(from: shared, now: .now)
                if let first = report.autoAttached.first {
                    let extra = report.autoAttached.count - 1
                    let message = extra > 0
                        ? String(localized: "Added “\(first.title)” and \(extra) more to \(first.eventTitle)")
                        : String(localized: "Added “\(first.title)” to \(first.eventTitle)")
                    banner = Banner(message: message, undoTarget: nil)
                    await onContextChanged()
                }
            }
            items = try await store.pendingInbox()
            problem = nil
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }

    func attach(_ item: InboxItemValue, to event: TimelineEvent) async {
        await attach(item, toKey: event.key, eventTitle: event.title)
    }

    func attachToSuggestion(_ item: InboxItemValue) async {
        guard let suggestion = item.suggestion else { return }
        await attach(item, toKey: suggestion.eventKey, eventTitle: suggestion.eventTitle)
    }

    func dismiss(_ item: InboxItemValue) async {
        await run(message: String(localized: "Dismissed"), undoTarget: item.id) {
            try await self.store.dismissInbox(id: item.id)
        }
    }

    func undoLast() async {
        guard let target = banner?.undoTarget else { return }
        banner = nil
        do {
            try await store.restoreInbox(id: target)
            await onContextChanged()
            items = try await store.pendingInbox()
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }

    func clearBanner(_ id: UUID) {
        if banner?.id == id { banner = nil }
    }

    /// Events an item could be attached to: those around the time it was shared.
    func loadChoices(for item: InboxItemValue) async {
        do {
            let events = try await store.events(
                from: item.receivedAt.addingTimeInterval(-12 * 3600),
                to: item.receivedAt.addingTimeInterval(48 * 3600)
            )
            choices = events.filter { $0.syncState == .active && !$0.isAllDay }
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }

    // MARK: - Private

    private func attach(_ item: InboxItemValue, toKey key: EventKey, eventTitle: String) async {
        await run(message: String(localized: "Attached to \(eventTitle)"), undoTarget: item.id) {
            _ = try await self.store.attachInbox(id: item.id, to: key, now: .now)
        }
        await onContextChanged()
    }

    private func run(message: String, undoTarget: UUID, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            banner = Banner(message: message, undoTarget: undoTarget)
            items = try await store.pendingInbox()
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }
}

extension InboxPayloadKind {
    var symbol: String {
        switch self {
        case .url: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        }
    }
}
