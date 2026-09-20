import QuickLook
import SwiftUI
import TerminalAssetDomain

enum AddKind: String, Identifiable {
    case task
    case note
    case link

    var id: String { rawValue }

    var kind: ContextItemKind {
        switch self {
        case .task: .task
        case .note: .note
        case .link: .link
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .task: "New Task"
        case .note: "New Note"
        case .link: "New Link"
        }
    }
}

struct EventDetailView: View {
    @State private var model: EventDetailViewModel
    @State private var adding: AddKind?
    /// The attached file being previewed (Quick Look), if any.
    @State private var previewing: URL?
    private let today: TodayViewModel

    init(key: EventKey, today: TodayViewModel, initialAdding: AddKind? = nil) {
        self.today = today
        _model = State(initialValue: today.makeDetailModel(for: key))
        _adding = State(initialValue: initialAdding)
    }

    var body: some View {
        List {
            if let event = model.event {
                Section { header(event) }

                if event.syncState == .missing {
                    Section {
                        Label("This event is no longer in your calendar. Its context is kept.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if event.items.isEmpty {
                    Section { emptyState }
                } else {
                    itemSections(event)
                }
            } else if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(model.event?.title ?? String(localized: "Event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    addButton(.task, "Task", "checklist")
                    addButton(.note, "Note", "note.text")
                    addButton(.link, "Link", "link")
                } label: {
                    Label("Add Context", systemImage: "plus")
                }
                .disabled(model.event == nil)
            }
        }
        .sheet(item: $adding) { kind in
            AddContextSheet(kind: kind, model: model)
        }
        .quickLookPreview($previewing)
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
        // The event may not be stored yet when this screen opens (first sync still running), and a sync can
        // change it while it is open, so reload whenever Today's data changes.
        .onChange(of: today.events) {
            Task { await model.load() }
        }
    }

    // MARK: - Sections

    private func header(_ event: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.title2.weight(.bold))
            Text(event.startDate.formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(TimeText.range(of: event))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Editing the event itself (time, guests, alerts) belongs to the Calendar app; this hands it over.
            if event.syncState == .active, let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)") {
                Link(destination: url) {
                    Label("Open in Calendar", systemImage: "calendar")
                }
                .font(.subheadline)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func itemSections(_ event: TimelineEvent) -> some View {
        let tasks = event.items.filter { $0.kind == .task }
        let notes = event.items.filter { $0.kind == .note }
        let links = event.items.filter { $0.kind == .link }
        let files = event.items.filter { $0.kind == .file || $0.kind == .image }

        if !tasks.isEmpty {
            Section("Tasks") {
                ForEach(tasks) { task in
                    Button {
                        Task { await model.setTask(task.id, done: !task.isDone) }
                    } label: {
                        Label {
                            Text(task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(task.isDone ? .secondary : .primary)
                        } icon: {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityValue(task.isDone ? String(localized: "Done") : String(localized: "Not done"))
                    .swipeActions { deleteAction(task.id) }
                }
            }
        }

        if !notes.isEmpty {
            Section("Notes") {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.body.weight(.medium))
                        if let detail = note.detail {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { deleteAction(note.id) }
                }
            }
        }

        if !files.isEmpty {
            Section("Files") {
                ForEach(files) { file in
                    Button {
                        previewing = model.attachmentURL(for: file)
                    } label: {
                        Label(file.title, systemImage: file.kind == .image ? "photo" : "doc")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityHint("Opens a preview")
                    .swipeActions { deleteAction(file.id) }
                }
            }
        }

        if !links.isEmpty {
            Section("Links") {
                ForEach(links) { link in
                    if let url = link.url {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(link.title).font(.body.weight(.medium))
                                Text(url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions { deleteAction(link.id) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No context yet")
                .font(.headline)
            Text("Add tasks, notes or links. They'll be shown on Today when this event is close.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Task") { adding = .task }
                Button("Note") { adding = .note }
                Button("Link") { adding = .link }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func addButton(_ kind: AddKind, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button { adding = kind } label: { Label(title, systemImage: symbol) }
    }

    private func deleteAction(_ id: UUID) -> some View {
        Button(role: .destructive) {
            Task { await model.delete(id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
