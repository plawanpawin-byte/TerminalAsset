import Foundation
import Observation

@MainActor
@Observable
final class InboxViewModel {
    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        let item: InboxItem
        let index: Int
    }

    private(set) var items: [InboxItem]
    private(set) var undo: UndoAction?

    init(items: [InboxItem]) {
        self.items = items
    }

    func attach(_ item: InboxItem, to eventTitle: String) {
        remove(item, message: "Attached to \(eventTitle)")
    }

    func dismiss(_ item: InboxItem) {
        remove(item, message: "Dismissed")
    }

    func undoLast() {
        guard let undo else { return }
        items.insert(undo.item, at: min(undo.index, items.count))
        self.undo = nil
    }

    func clearUndo() {
        undo = nil
    }

    private func remove(_ item: InboxItem, message: String) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        undo = UndoAction(message: message, item: item, index: index)
    }
}
