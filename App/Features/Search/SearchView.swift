import SwiftUI
import TerminalAssetDomain

struct SearchView: View {
    @Bindable var model: SearchViewModel
    let today: TodayViewModel

    var body: some View {
        NavigationStack {
            List {
                if let problem = model.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if model.trimmedQuery.isEmpty {
                    suggestions
                } else {
                    resultsSection
                }
            }
            .navigationTitle("Search")
            .searchable(text: $model.query, prompt: "Events, notes, links, tasks")
            .searchScopes($model.scope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .onSubmit(of: .search) { model.commit() }
            .onChange(of: model.query) { model.scheduleSearch() }
            .onChange(of: model.scope) { model.scheduleSearch() }
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: today)
            }
            .task { await model.loadCorpus() }
            // The first calendar sync (or a share attached from the Inbox) can finish after this screen first
            // loaded, so the searchable corpus is rebuilt whenever Today's data changes.
            .onChange(of: today.events) {
                Task { await model.loadCorpus() }
            }
        }
    }

    // MARK: - Empty query

    @ViewBuilder
    private var suggestions: some View {
        if !model.isReady {
            Section { ProgressView().frame(maxWidth: .infinity) }
        } else if !model.relevantNow.isEmpty {
            Section {
                ForEach(model.relevantNow) { hit in
                    ResultRow(hit: hit)
                }
            } header: {
                Label("Relevant now", systemImage: "sparkles")
            } footer: {
                Text("Open items for the event running now or starting soon.")
            }
        } else if !model.hasContent {
            Section {
                ContentUnavailableView(
                    "Nothing to search yet",
                    systemImage: "magnifyingglass",
                    description: Text("Add tasks, notes and links to your events, or share things into the Inbox. They'll be searchable here.")
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                Label("Nothing time-sensitive right now", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Type to search everything you've attached to your events.")
            }
        }

        if !model.recentSearches.isEmpty {
            Section {
                ForEach(model.recentSearches, id: \.self) { term in
                    Button {
                        model.query = term
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("Recent searches")
                    Spacer()
                    Button("Clear") { model.clearRecentSearches() }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if model.results.isEmpty {
            ContentUnavailableView.search(text: model.trimmedQuery)
                .listRowBackground(Color.clear)
        } else {
            Section("\(model.results.count) result\(model.results.count == 1 ? "" : "s")") {
                ForEach(model.results) { hit in
                    ResultRow(hit: hit)
                }
            }
        }
    }
}

private struct ResultRow: View {
    let hit: SearchHit

    private var document: SearchDocument { hit.document }

    var body: some View {
        NavigationLink(value: document.eventKey) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: document.kind.symbol(isDone: document.isDone))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.body.weight(.medium))
                        .strikethrough(document.isDone)
                    if !hit.snippet.isEmpty {
                        Text(hit.snippet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(eventLine)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(hit.signals, id: \.self) { signal in
                            Pill(text: signal.text, symbol: symbol(for: signal), tint: tint(for: signal))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var eventLine: String {
        let when = document.eventStart.formatted(date: .abbreviated, time: .shortened)
        return document.kind == .event ? when : "\(document.eventTitle) · \(when)"
    }

    private func symbol(for signal: SearchSignal) -> String {
        switch signal.kind {
        case .match: "text.magnifyingglass"
        case .temporal: "clock"
        case .recent: "calendar.badge.clock"
        }
    }

    private func tint(for signal: SearchSignal) -> Color {
        signal.kind == .temporal ? .accentColor : .secondary
    }
}
