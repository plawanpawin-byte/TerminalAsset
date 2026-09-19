import SwiftUI

struct SearchView: View {
    @State private var model: SearchViewModel

    init() {
        #if DEBUG
        _model = State(initialValue: SearchViewModel(query: LaunchOptions.query))
        #else
        _model = State(initialValue: SearchViewModel())
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                if model.trimmedQuery.isEmpty && model.scope == .all {
                    suggestions
                } else {
                    resultsSection
                }
                Section { SampleDataNote() }
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Search")
            .searchable(text: $model.query, prompt: "Files, notes, links, events")
            .searchScopes($model.scope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
        }
    }

    // MARK: - Empty query

    @ViewBuilder
    private var suggestions: some View {
        Section {
            ForEach(model.relevantNow) { result in
                ResultRow(result: result)
            }
        } header: {
            Label("Relevant now", systemImage: "sparkles")
        } footer: {
            Text("Ranked by how close the event is, how the item relates to it, and how recently you used it.")
        }

        Section("Recent searches") {
            ForEach(model.recentSearches, id: \.self) { term in
                Button {
                    model.query = term
                } label: {
                    Label(term, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        let results = model.results
        if results.isEmpty {
            ContentUnavailableView.search(text: model.trimmedQuery)
                .listRowBackground(Color.clear)
        } else {
            Section("\(results.count) result\(results.count == 1 ? "" : "s")") {
                ForEach(results) { result in
                    ResultRow(result: result)
                }
            }
        }
    }
}

private struct ResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.kind.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body.weight(.medium))
                Text(result.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let event = result.eventTitle {
                    Label(event, systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(result.signals, id: \.self) { signal in
                            Pill(text: signal.text, symbol: signal.symbol)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Search") {
    SearchView()
}
