import SwiftUI
import TerminalAssetDomain

struct SearchView: View {
    @Bindable var model: SearchViewModel
    let today: TodayViewModel

    @Environment(\.scenePhase) private var scenePhase

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
            // "Relevant now" and the time wording go stale as the day goes on, even if nothing else changed:
            // refresh when the app comes back and every minute while this tab is showing.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.loadCorpus() } }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await model.refreshRelevance()
                }
            }
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
            Section("\(model.results.count) results") {
                ForEach(model.results) { hit in
                    ResultRow(hit: hit)
                }
            }
        }
    }
}

private struct ResultRow: View {
    let hit: SearchHit

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var iconBox: CGFloat = 32

    private var document: SearchDocument { hit.document }
    /// One-line details are cut at normal sizes; at accessibility sizes they wrap instead of leaving a few letters.
    private var detailLines: Int? { typeSize.isAccessibilitySize ? nil : 1 }

    /// Icon beside the text, or above it at accessibility sizes so the text keeps the full width.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    var body: some View {
        NavigationLink(value: document.eventKey) {
            layout {
                Image(systemName: document.kind.symbol(isDone: document.isDone))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: iconBox, height: iconBox)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.body.weight(.medium))
                        .strikethrough(document.isDone)
                        .lineLimit(detailLines == nil ? nil : 2)
                    if !hit.snippet.isEmpty {
                        Text(hit.snippet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(detailLines)
                    } else if document.kind == .task {
                        Text(document.isDone ? LocalizedStringKey("Done") : LocalizedStringKey("Open task"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(eventLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(detailLines)
                    if let reasons {
                        Text(reasons)
                            .font(.caption)
                            .foregroundStyle(hasTemporalSignal ? Color.accentColor : .secondary)
                            .lineLimit(detailLines)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var eventLine: String {
        let when = TimeText.compact(start: document.eventStart, isAllDay: document.eventIsAllDay)
        return document.kind == .event ? when : "\(document.eventTitle) · \(when)"
    }

    private var hasTemporalSignal: Bool {
        hit.signals.contains { $0.kind == .temporal }
    }

    /// Why the result ranked here, on one quiet line ("Event is happening now · Added today").
    private var reasons: String? {
        hit.signals.isEmpty ? nil : hit.signals.map(\.reason.text).joined(separator: " · ")
    }
}

extension SearchSignal.Reason {
    var text: String {
        switch self {
        case .matchesTitle: String(localized: "Matches title")
        case .matchesLink: String(localized: "Matches link")
        case .matchesText: String(localized: "Matches text")
        case .matchesEventName: String(localized: "Matches event name")
        case .matches: String(localized: "Matches")
        case .eventHappeningNow: String(localized: "Event is happening now")
        case .eventStartsInMinutes(let minutes): String(localized: "Event starts in \(minutes) min")
        case .eventStartsInHours(let hours): String(localized: "Event starts in \(hours) h")
        case .eventStartsTomorrow: String(localized: "Event starts tomorrow")
        case .eventStartsInDays(let days): String(localized: "Event starts in \(days) days")
        case .eventWasEarlierToday: String(localized: "Event was earlier today")
        case .eventWasYesterday: String(localized: "Event was yesterday")
        case .eventWasDaysAgo(let days): String(localized: "Event was \(days) days ago")
        case .addedToday: String(localized: "Added today")
        case .addedYesterday: String(localized: "Added yesterday")
        case .addedDaysAgo(let days): String(localized: "Added \(days) days ago")
        }
    }
}
