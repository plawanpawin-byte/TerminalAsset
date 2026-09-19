import SwiftUI

struct InboxView: View {
    let model: InboxViewModel

    @State private var choosing: InboxItem?
    @State private var showingHowTo = false

    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty {
                    ContentUnavailableView(
                        "Inbox zero",
                        systemImage: "tray",
                        description: Text("Things you share from Safari, Photos and Files land here until they're attached to an event.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingHowTo = true
                    } label: {
                        Label("How to add", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .overlay(alignment: .bottom) { undoBanner }
            .sheet(item: $choosing) { item in
                EventPickerSheet(item: item) { title in
                    model.attach(item, to: title)
                }
            }
            .sheet(isPresented: $showingHowTo) { ShareHowToSheet() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.items) { item in
                    InboxRow(
                        item: item,
                        onAttach: { title in model.attach(item, to: title) },
                        onChoose: { choosing = item }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.dismiss(item)
                        } label: {
                            Label("Dismiss", systemImage: "xmark.bin")
                        }
                    }
                }
            } header: {
                Text("\(model.items.count) waiting")
            } footer: {
                Text("Share anything to TerminalAsset and it lands here with a suggested event. You never have to file it yourself.")
            }
            Section { SampleDataNote() }
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let undo = model.undo {
            HStack {
                Text(undo.message)
                    .font(.subheadline)
                Spacer()
                Button("Undo") { model.undoLast() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(6))
                model.clearUndo()
            }
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem
    let onAttach: (String) -> Void
    let onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text("\(item.source) · \(item.receivedAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let suggestion = item.suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Suggested: **\(suggestion.eventTitle)**")
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    }
                    .font(.subheadline)
                    Text(suggestion.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Attach") { onAttach(suggestion.eventTitle) }
                            .buttonStyle(.borderedProminent)
                        Button("Choose…", action: onChoose)
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Label("No confident match", systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose event…", action: onChoose)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
        .buttonStyle(.borderless)
    }
}

private struct EventPickerSheet: View {
    let item: InboxItem
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(UIFixtures.eventChoices()) { choice in
                Button {
                    onPick(choice.title)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title).foregroundStyle(.primary)
                        Text(choice.timeText).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Attach to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ShareHowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                step("1", "safari", "Open anything", "A web page in Safari, a photo, a file or a message.")
                step("2", "square.and.arrow.up", "Tap Share", "Choose TerminalAsset from the share sheet.")
                step("3", "sparkles", "Pick where it goes", "Attach to the current event, an upcoming one, or let TerminalAsset decide.")
            }
            .navigationTitle("Add to Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func step(_ number: String, _ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)").font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
