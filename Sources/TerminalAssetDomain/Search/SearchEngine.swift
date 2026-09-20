import Foundation

/// Deterministic local search over events and their context. No network, no AI, no persistence types.
///
/// Score = lexical × (0.55 + 0.30 × temporal + 0.15 × recency), each factor 0...1.
/// - **Lexical**: every query word must match somewhere (AND). A word scores by where it matches:
///   title 3, the event's name 1.5, body 1, times 1.0 for an exact word, 0.7 for a prefix (so search-as-you-type
///   works). Normalized by 3 × number of words.
/// - **Temporal**: how close the related event is: 1.0 while it runs, decaying from 0.9 to 0.4 over the next
///   48 hours, 0.4 for the past week, 0.1 otherwise.
/// - **Recency**: 1 / (1 + age in days / 14).
///
/// Assumptions and trade-offs:
/// - Lexical is a multiplier, not an addend, so an item that does not match the words can never rank because
///   it is merely close in time. The cost: a typo returns nothing. Semantic matching (embeddings) is a later
///   layer that would supply a second lexical-like signal.
/// - The time and recency weights are hand-set starting points, not tuned on real usage.
/// - Words are split on non-alphanumerics. Scripts written without spaces (Thai) get substring matching as a
///   fallback; a language-aware tokenizer (NaturalLanguage) can replace `words(in:)` later.
public enum SearchEngine {
    // MARK: - Query

    public static func search(
        _ text: String,
        scope: SearchScope,
        in documents: [SearchDocument],
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 50
    ) -> [SearchHit] {
        let queryWords = words(in: text).filter { $0.count >= 2 || $0.allSatisfy(\.isNumber) }
        guard !queryWords.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for document in documents where scope == .all || document.kind.scope == scope {
            guard let match = lexicalMatch(queryWords, in: document) else { continue }
            let temporal = temporalWeight(of: document, at: now, calendar: calendar)
            let recency = recencyWeight(of: document, at: now)
            let score = match.score * (0.55 + 0.30 * temporal.weight + 0.15 * recency)

            var signals = [SearchSignal(kind: .match, reason: match.reason)]
            if let reason = temporal.reason { signals.append(SearchSignal(kind: .temporal, reason: reason)) }
            if let reason = recencyReason(of: document, at: now, calendar: calendar) {
                signals.append(SearchSignal(kind: .recent, reason: reason))
            }

            hits.append(SearchHit(
                document: document,
                score: score,
                snippet: snippet(for: document, around: queryWords),
                signals: signals
            ))
        }
        return Array(hits.sorted(by: ranked).prefix(limit))
    }

    /// "What is relevant now?": open context attached to the event running now or starting soon.
    /// Used before the user types anything.
    public static func relevantNow(
        in documents: [SearchDocument],
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [SearchHit] {
        var hits: [SearchHit] = []
        for document in documents
        where document.kind != .event && !(document.kind == .task && document.isDone) && document.isEventActive {
            let temporal = temporalWeight(of: document, at: now, calendar: calendar)
            // Only the running event and upcoming events count; the recent past is not "now".
            guard temporal.isCurrentOrUpcoming else { continue }
            let recency = recencyWeight(of: document, at: now)

            var signals: [SearchSignal] = []
            if let reason = temporal.reason { signals.append(SearchSignal(kind: .temporal, reason: reason)) }
            if let reason = recencyReason(of: document, at: now, calendar: calendar) {
                signals.append(SearchSignal(kind: .recent, reason: reason))
            }

            hits.append(SearchHit(
                document: document,
                score: temporal.weight * (0.7 + 0.3 * recency),
                snippet: snippet(for: document, around: []),
                signals: signals
            ))
        }
        return Array(hits.sorted(by: ranked).prefix(limit))
    }

    // MARK: - Lexical

    private struct LexicalMatch {
        let score: Double
        let reason: SearchSignal.Reason
    }

    private static func lexicalMatch(_ queryWords: [String], in document: SearchDocument) -> LexicalMatch? {
        let titleWords = words(in: document.title)
        let bodyWords = words(in: document.body)
        let eventWords = words(in: document.eventTitle)

        var total = 0.0
        var matchedTitle = false
        var matchedBody = false
        var matchedEvent = false

        for word in queryWords {
            let title = 3.0 * matchFactor(word, in: titleWords)
            let event = document.kind == .event ? 0 : 1.5 * matchFactor(word, in: eventWords)
            let body = 1.0 * matchFactor(word, in: bodyWords)
            let best = max(title, event, body)
            guard best > 0 else { return nil }
            total += best
            if best == title { matchedTitle = true } else if best == event { matchedEvent = true } else { matchedBody = true }
        }

        let reason: SearchSignal.Reason
        if matchedTitle {
            reason = .matchesTitle
        } else if matchedBody {
            reason = document.kind == .link ? .matchesLink : .matchesText
        } else if matchedEvent {
            reason = .matchesEventName
        } else {
            reason = .matches
        }
        return LexicalMatch(score: total / (3.0 * Double(queryWords.count)), reason: reason)
    }

    private static func matchFactor(_ query: String, in words: [String]) -> Double {
        var best = 0.0
        for word in words {
            if word == query { return 1.0 }
            if word.hasPrefix(query) {
                best = max(best, 0.7)
            } else if !query.allSatisfy(\.isASCII), word.contains(query) {
                best = max(best, 0.5)
            }
        }
        return best
    }

    static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Time

    private struct TemporalWeight {
        let weight: Double
        let reason: SearchSignal.Reason?
        let isCurrentOrUpcoming: Bool
    }

    private static func temporalWeight(of document: SearchDocument, at now: Date, calendar: Calendar) -> TemporalWeight {
        if document.eventStart <= now && now < document.eventEnd {
            return TemporalWeight(weight: 1.0, reason: .eventHappeningNow, isCurrentOrUpcoming: true)
        }
        if document.eventStart > now {
            let hours = document.eventStart.timeIntervalSince(now) / 3600
            guard hours <= 48 else {
                return TemporalWeight(weight: 0.1, reason: nil, isCurrentOrUpcoming: false)
            }
            let weight = 0.9 - 0.5 * (hours / 48)
            return TemporalWeight(
                weight: weight,
                reason: futureReason(hours: hours, days: dayOffset(from: now, to: document.eventStart, calendar: calendar)),
                isCurrentOrUpcoming: true
            )
        }
        let daysAgo = now.timeIntervalSince(document.eventEnd) / 86_400
        if daysAgo <= 7 {
            return TemporalWeight(
                weight: 0.4,
                reason: pastReason(days: -dayOffset(from: now, to: document.eventEnd, calendar: calendar)),
                isCurrentOrUpcoming: false
            )
        }
        return TemporalWeight(weight: 0.1, reason: nil, isCurrentOrUpcoming: false)
    }

    /// How many calendar days `date` is from `now` (0 = the same day, 1 = tomorrow, -1 = yesterday). Wording follows
    /// the calendar, not elapsed hours: 11 hours ago can be yesterday, and 46 hours ahead can be the day after tomorrow.
    private static func dayOffset(from now: Date, to date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    private static func futureReason(hours: Double, days: Int) -> SearchSignal.Reason {
        if days >= 2 { return .eventStartsInDays(days) }
        if days == 1 { return .eventStartsTomorrow }
        if hours < 1 { return .eventStartsInMinutes(max(1, Int((hours * 60).rounded()))) }
        return .eventStartsInHours(Int(hours.rounded()))
    }

    private static func pastReason(days: Int) -> SearchSignal.Reason {
        if days <= 0 { return .eventWasEarlierToday }
        if days == 1 { return .eventWasYesterday }
        return .eventWasDaysAgo(days)
    }

    private static func recencyWeight(of document: SearchDocument, at now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(document.createdAt)) / 86_400
        return 1 / (1 + ageDays / 14)
    }

    private static func recencyReason(
        of document: SearchDocument,
        at now: Date,
        calendar: Calendar
    ) -> SearchSignal.Reason? {
        guard document.kind != .event, document.createdAt <= now else { return nil }
        let daysAgo = -dayOffset(from: now, to: document.createdAt, calendar: calendar)
        guard daysAgo <= 7 else { return nil }
        if daysAgo <= 0 { return .addedToday }
        if daysAgo == 1 { return .addedYesterday }
        return .addedDaysAgo(daysAgo)
    }

    // MARK: - Presentation helpers

    private static func ranked(_ lhs: SearchHit, _ rhs: SearchHit) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.document.title != rhs.document.title { return lhs.document.title < rhs.document.title }
        return lhs.document.id < rhs.document.id
    }

    /// A short excerpt of the body, centred on the first match when there is one.
    private static func snippet(for document: SearchDocument, around queryWords: [String]) -> String {
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        let limit = 90
        guard body.count > limit else { return body }

        let lowered = body.lowercased()
        let matchStart = queryWords
            .compactMap { lowered.range(of: $0)?.lowerBound }
            .min()
        guard let matchStart else { return String(body.prefix(limit)) + "…" }

        let offset = lowered.distance(from: lowered.startIndex, to: matchStart)
        let start = max(0, offset - 20)
        let begin = body.index(body.startIndex, offsetBy: min(start, body.count))
        let excerpt = String(body[begin...].prefix(limit))
        return (start > 0 ? "…" : "") + excerpt + (body.count - start > limit ? "…" : "")
    }
}
