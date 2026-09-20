import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class SearchViewModel {
    var query: String
    var scope: SearchScope = .all

    private(set) var results: [SearchHit] = []
    private(set) var relevantNow: [SearchHit] = []
    private(set) var isReady = false
    private(set) var hasContent = false
    private(set) var problem: String?
    private(set) var recentSearches: [String]

    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private var corpus: [SearchDocument] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Recent searches are a UI preference, not domain data, so a plain default is appropriate here.
    private static let recentKey = "search.recent"
    private static let recentLimit = 8

    init(store: ContextStore, query: String = "") {
        self.store = store
        self.query = query
        self.recentSearches = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads events and context from the database (off the main actor) and refreshes "Relevant now".
    func loadCorpus(now: Date = .now) async {
        do {
            let documents = try await store.searchCorpus(now: now)
            corpus = documents
            hasContent = documents.contains { $0.kind != .event }
            relevantNow = await Task.detached(priority: .userInitiated) {
                SearchEngine.relevantNow(in: documents, now: now)
            }.value
            isReady = true
            problem = nil
            scheduleSearch()
        } catch {
            problem = TodayViewModel.message(for: error)
            isReady = true
        }
    }

    /// Debounced, cancellable ranking. Runs off the main actor so typing never waits on scoring.
    func scheduleSearch() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = []
            return
        }
        let scope = scope
        let documents = corpus
        let now = Date()

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) {
                SearchEngine.search(text, scope: scope, in: documents, now: now)
            }.value
            guard !Task.isCancelled else { return }
            results = hits
        }
    }

    /// Remembers a search when the user submits it.
    func commit() {
        let text = trimmedQuery
        guard text.count >= 2 else { return }
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        updated.insert(text, at: 0)
        recentSearches = Array(updated.prefix(Self.recentLimit))
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }
}

extension SearchScope {
    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .events: String(localized: "Events")
        case .tasks: String(localized: "Tasks")
        case .notes: String(localized: "Notes")
        case .links: String(localized: "Links")
        case .files: String(localized: "Files")
        }
    }
}

extension SearchDocumentKind {
    func symbol(isDone: Bool = false) -> String {
        switch self {
        case .event: "calendar"
        case .task: isDone ? "checkmark.circle.fill" : "checklist"
        case .note: "note.text"
        case .link: "link"
        case .file: "doc.text"
        case .image: "photo"
        case .voice: "waveform"
        }
    }
}
