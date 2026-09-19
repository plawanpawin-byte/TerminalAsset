import SwiftUI
import TerminalAssetDomain

struct AddContextSheet: View {
    let kind: AddKind
    let model: EventDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var urlString = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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
            .navigationTitle(kind.title)
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
            if let message = await model.add(draft) {
                errorMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }
}
