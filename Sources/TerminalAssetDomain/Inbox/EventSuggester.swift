import Foundation

public struct EventSuggestion: Sendable, Hashable {
    public let eventKey: EventKey
    public let eventTitle: String
    /// Human-readable signals, e.g. "Happening now · similar topic".
    public let reason: String
    /// 0...1. Only suggestions at or above `EventSuggester.minimumConfidence` are returned.
    public let confidence: Double

    public init(eventKey: EventKey, eventTitle: String, reason: String, confidence: Double) {
        self.eventKey = eventKey
        self.eventTitle = eventTitle
        self.reason = reason
        self.confidence = confidence
    }
}

/// Deterministic matching of a shared item to an event. No AI: time and shared words only.
///
/// Score = 0.6 × temporal + 0.4 × lexical, both 0...1.
/// - Temporal: 1.0 while the event is running; up to 0.8 for an event starting within 90 minutes
///   (decaying with distance); 0.5 within 30 minutes after it ended (people often share right after a meeting).
/// - Lexical: share of the event's meaningful words that also appear in the shared text.
///
/// Trade-offs: additive rather than multiplicative, so a strong time signal alone can still suggest an event
/// (the spec's multiplicative form would zero out anything with no word overlap). Tokenization splits on
/// non-alphanumerics, which works for space-separated languages but not for Thai; a language-aware tokenizer
/// (NaturalLanguage) can replace `tokens(in:)` later without changing callers.
public enum EventSuggester {
    public static let minimumConfidence = 0.35

    public static func suggest(text: String, at moment: Date, events: [TimelineEvent]) -> EventSuggestion? {
        let sharedTokens = tokens(in: text)
        var best: (event: TimelineEvent, score: Double, reason: String)?

        for event in events where event.syncState == .active && !event.isAllDay {
            let temporal = temporalScore(of: event, at: moment)
            let lexical = lexicalScore(of: event, against: sharedTokens)
            guard temporal.value > 0 || lexical > 0 else { continue }

            let score = 0.6 * temporal.value + 0.4 * lexical
            var parts: [String] = []
            if let label = temporal.label { parts.append(label) }
            if lexical > 0 { parts.append("similar topic") }

            let isBetter: Bool
            if let current = best {
                isBetter = score > current.score
                    || (score == current.score && event.startDate < current.event.startDate)
            } else {
                isBetter = true
            }
            if isBetter {
                best = (event, score, parts.joined(separator: " · "))
            }
        }

        guard let best, best.score >= minimumConfidence else { return nil }
        return EventSuggestion(
            eventKey: best.event.key,
            eventTitle: best.event.title,
            reason: best.reason.prefix(1).uppercased() + best.reason.dropFirst(),
            confidence: min(best.score, 1)
        )
    }

    /// The event a "Current event" or "Upcoming event" choice refers to, judged at the moment of sharing.
    public static func resolve(intent: ShareIntent, at moment: Date, events: [TimelineEvent]) -> TimelineEvent? {
        let candidates = events.filter { $0.syncState == .active && !$0.isAllDay }
        switch intent {
        case .decide:
            return nil
        case .currentEvent:
            return candidates
                .filter { $0.startDate <= moment && moment < $0.endDate }
                .max { $0.startDate < $1.startDate }
        case .upcomingEvent:
            return candidates
                .filter { $0.startDate > moment }
                .min { $0.startDate < $1.startDate }
        }
    }

    // MARK: - Signals

    private struct TemporalSignal {
        let value: Double
        let label: String?

        static let none = TemporalSignal(value: 0, label: nil)
    }

    private static func temporalScore(of event: TimelineEvent, at moment: Date) -> TemporalSignal {
        if event.startDate <= moment && moment < event.endDate {
            return TemporalSignal(value: 1, label: "happening now")
        }
        if event.startDate > moment {
            let minutes = event.startDate.timeIntervalSince(moment) / 60
            guard minutes <= 90 else { return .none }
            let value = 0.2 + 0.6 * (1 - minutes / 90)
            return TemporalSignal(value: value, label: "starts in \(Int(minutes.rounded())) min")
        }
        let minutesAgo = moment.timeIntervalSince(event.endDate) / 60
        guard minutesAgo <= 30 else { return .none }
        return TemporalSignal(value: 0.5, label: "ended \(Int(minutesAgo.rounded())) min ago")
    }

    private static func lexicalScore(of event: TimelineEvent, against shared: Set<String>) -> Double {
        guard !shared.isEmpty else { return 0 }
        let eventTokens = tokens(in: ([event.title] + event.items.map(\.title)).joined(separator: " "))
        guard !eventTokens.isEmpty else { return 0 }
        let overlap = eventTokens.intersection(shared).count
        return min(1, Double(overlap) / Double(min(eventTokens.count, 4)))
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "your", "you", "are", "was", "how", "what",
        "meeting", "call", "sync", "review"
    ]

    static func tokens(in text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        return Set(words)
    }
}
