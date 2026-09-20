import SwiftUI
import TerminalAssetDomain

struct ShareView: View {
    @Bindable var model: ShareModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .loading:
                    Section { ProgressView().frame(maxWidth: .infinity) }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                case .ready, .saving:
                    contentSections
                }
            }
            .navigationTitle("Add to TerminalAsset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { if await model.save() { onDone() } }
                    }
                    .disabled(model.phase != .ready)
                }
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var contentSections: some View {
        Section {
            ForEach(Array(model.contents.enumerated()), id: \.offset) { _, content in
                Label(content.title, systemImage: symbol(for: content))
                    .lineLimit(2)
            }
        } header: {
            Text("Sharing")
        } footer: {
            if model.skipped > 0 {
                Text("\(model.skipped) items couldn't be read and won't be added.")
            }
        }

        Section {
            Picker("Attach to", selection: $model.intent) {
                Text("Let TerminalAsset decide").tag(ShareIntent.decide)
                Text("Current event").tag(ShareIntent.currentEvent)
                Text("Next event").tag(ShareIntent.upcomingEvent)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Attach to")
        } footer: {
            Text("You can change where it goes later in the TerminalAsset Inbox.")
        }
    }

    private func symbol(for content: SharedContent) -> String {
        switch content.payload {
        case .url: "link"
        case .text: "text.alignleft"
        case .file(_, let isImage): isImage ? "photo" : "doc"
        }
    }
}
