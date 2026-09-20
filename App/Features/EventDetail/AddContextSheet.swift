import SwiftUI
import TerminalAssetDomain

/// Adds a task, note or link, or (when `editing` is set) changes an existing one.
struct AddContextSheet: View {
    let kind: AddKind
    let model: EventDetailViewModel
    let editing: ContextItemValue?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var detail: String
    @State private var urlString: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(kind: AddKind, model: EventDetailViewModel, editing: ContextItemValue? = nil) {
        self.kind = kind
        self.model = model
        self.editing = editing
        // A link's title defaults to its address's host. That default is not something the user chose, so it is left
        // blank when editing: otherwise changing the address would keep the old host as the title.
        let isDefaultLinkTitle = editing?.kind == .link && editing?.title == editing?.url?.host(percentEncoded: false)
        _title = State(initialValue: isDefaultLinkTitle ? "" : (editing?.title ?? ""))
        _detail = State(initialValue: editing?.detail ?? "")
        _urlString = State(initialValue: editing?.url?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .task:
                    Section { TextField("What needs doing?", text: $title) }
                case .note:
                    Section {
                        TextField("Title", text: $title)
                        TextField("Details (optional)", text: $detail, axis: .vertical)
                            .lineLimit(3...8)
                    }
                case .link:
                    Section {
                        TextField("Web address", text: $urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Title (optional)", text: $title)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editing == nil ? kind.title : kind.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let draft = ContextItemDraft(kind: kind.kind, title: title, detail: detail, urlString: urlString)
        Task {
            let message: String?
            if let editing {
                message = await model.update(editing.id, with: draft)
            } else {
                message = await model.add(draft)
            }
            if let message {
                errorMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }
}
