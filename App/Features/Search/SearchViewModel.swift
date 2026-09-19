import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query: String
    var scope: SearchScope = .all

    let recentSearches: [String]
    @ObservationIgnored private let corpus: [SearchResult]

    init(
        query: String = "",
        corpus: [SearchResult] = UIFixtures.searchResults(),
        recentSearches: [String] = UIFixtures.recentSearches
    ) {
        self.query = query
        self.corpus = corpus
        self.recentSearches = recentSearches
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What matters right now, before the user types anything: the highest-ranked items.
    var relevantNow: [SearchResult] {
        Array(corpus.sorted { $0.score > $1.score }.prefix(3))
    }

    var results: [SearchResult] {
        let needle = trimmedQuery.lowercased()
        return corpus
            .filter { scope == .all || $0.kind.scope == scope }
            .filter { result in
                needle.isEmpty
                    || result.title.lowercased().contains(needle)
                    || result.snippet.lowercased().contains(needle)
                    || (result.eventTitle?.lowercased().contains(needle) ?? false)
            }
            .sorted { $0.score > $1.score }
    }
}
