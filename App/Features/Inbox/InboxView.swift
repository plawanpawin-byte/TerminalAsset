import SwiftUI
import TerminalAssetDomain

struct InboxView: View {
    let model: InboxViewModel

    @State private var choosing: InboxItemValue?
    @State private var showingHowTo = false

    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty {
                    emptyState
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
            .overlay(alignment: .bottom) { banner }
            .sheet(item: $choosing) { item in
                EventPickerSheet(item: item, model: model)
            }
            .sheet(isPresented: $showingHowTo) { ShareHowToSheet() }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var emptyState: some View {
        if model.sharingAvailable {
            ContentUnavailableView(
                "Inbox zero",
                systemImage: "tray",
                description: Text("Things you share from Safari, Photos and Files land here until they're attached to an event.")
            )
        } else {
            ContentUnavailableView(
                "Sharing isn't set up",
                systemImage: "exclamationmark.triangle",
                description: Text("This build can't receive shared items yet. Everything else keeps working.")
            )
        }
    }

    private var list: some View {
        List {
            if let problem = model.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(model.items) { item in
                    InboxRow(
                        item: item,
                        onAttach: { Task { await model.attachToSuggestion(item) } },
                        onChoose: { choosing = item }
                    )
                    .swipeActions(edge: .leading) {
                        if item.suggestion != nil {
                            Button {
                                Task { await model.attachToSuggestion(item) }
                            } label: {
                                Label("Attach", systemImage: "paperclip")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await model.dismiss(item) }
                        } label: {
                            Label("Dismiss", systemImage: "xmark.bin")
                        }
                    }
                    .contextMenu {
                        if let suggestion = item.suggestion {
                            Button {
                                Task { await model.attachToSuggestion(item) }
                            } label: {
                                Label("Attach to \(suggestion.eventTitle)", systemImage: "paperclip")
                            }
                        }
                        Button {
                            choosing = item
                        } label: {
                            Label("Choose event…", systemImage: "calendar")
                        }
                        Button(role: .destructive) {
                            Task { await model.dismiss(item) }
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
        }
        .sensoryFeedback(.success, trigger: model.banner?.id)
    }

    @ViewBuilder
    private var banner: some View {
        if let banner = model.banner {
            HStack {
                Text(banner.message)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                if banner.undoTarget != nil {
                    Button("Undo") { Task { await model.undoLast() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: banner.id) {
                try? await Task.sleep(for: .seconds(6))
                model.clearBanner(banner.id)
            }
        }
    }
}

private struct InboxRow: View {
    let item: InboxItemValue
    let onAttach: () -> Void
    let onChoose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(verbatim: "\(item.subtitle.text) · \(item.receivedAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                destination
            }
        }
        .padding(.vertical, 4)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var destination: some View {
        if let suggestion = item.suggestion {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Suggested: **\(suggestion.eventTitle)**")
                        .font(.subheadline)
                    Text(suggestion.reasonText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Attach", action: onAttach)
                        .buttonStyle(.borderedProminent)
                    Button("Choose…", action: onChoose)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No confident match")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Choose event…", action: onChoose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct EventPickerSheet: View {
    let item: InboxItemValue
    let model: InboxViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.choices.isEmpty {
                    ContentUnavailableView(
                        "No events nearby",
                        systemImage: "calendar",
                        description: Text("There are no calendar events around the time this was shared.")
                    )
                } else {
                    List(model.choices) { event in
                        Button {
                            Task {
                                await model.attach(item, to: event)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).foregroundStyle(.primary)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            .task { await model.loadChoices(for: item) }
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
                step("3", "sparkles", "Pick where it goes", "Attach to the current event, the next one, or let TerminalAsset decide.")
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

    private func step(_ number: String, _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: "\(number).")
                    Text(title)
                }
                .font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension InboxSubtitle {
    var text: String {
        switch self {
        case .host(let host): host
        case .link: String(localized: "Link")
        case .text: String(localized: "Text")
        case .excerpt(let excerpt): excerpt
        case .image: String(localized: "Image")
        case .fileType(let type): String(localized: "\(type) file")
        case .file: String(localized: "File")
        }
    }
}

extension EventSuggestion {
    /// "Happening now · Similar topic": the signals behind the suggestion, in the user's language.
    var reasonText: String {
        reasons.map { reason in
            switch reason {
            case .happeningNow: String(localized: "Happening now")
            case .startsInMinutes(let minutes): String(localized: "Starts in \(minutes) min")
            case .endedMinutesAgo(let minutes): String(localized: "Ended \(minutes) min ago")
            case .similarTopic: String(localized: "Similar topic")
            }
        }.joined(separator: " · ")
    }
}
