import Foundation
import Testing
@testable import TerminalAssetDomain

private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)

private func doc(
    _ id: String,
    _ kind: SearchDocumentKind = .note,
    title: String,
    body: String = "",
    event: String = "ISO Audit Preparation",
    eventStart: Date = now - 20 * 60,
    eventLength: TimeInterval = hour,
    createdAt: Date = now - hour,
    isDone: Bool = false
) -> SearchDocument {
    SearchDocument(
        id: id, kind: kind, title: title, body: body,
        eventKey: EventKey(rawValue: "k-\(event)"), eventTitle: event,
        eventStart: eventStart, eventEnd: eventStart + eventLength,
        createdAt: createdAt, isDone: isDone
    )
}

private func ids(_ hits: [SearchHit]) -> [String] { hits.map(\.id) }

@Suite("SearchEngine")
struct SearchEngineTests {
    @Test func everyQueryWordMustMatch() {
        let docs = [
            doc("a", title: "Risk register summary"),
            doc("b", title: "Risk appetite statement")
        ]
        #expect(ids(SearchEngine.search("risk register", scope: .all, in: docs, now: now)) == ["a"])
    }

    @Test func prefixesMatchSoSearchAsYouTypeWorks() {
        let docs = [doc("a", title: "Vendor questionnaire")]
        #expect(ids(SearchEngine.search("vend", scope: .all, in: docs, now: now)) == ["a"])
        #expect(ids(SearchEngine.search("questionn", scope: .all, in: docs, now: now)) == ["a"])
    }

    @Test func aTitleMatchOutranksABodyMatch() {
        let inTitle = doc("title", title: "Corrective actions", body: "notes")
        let inBody = doc("body", title: "Meeting notes", body: "Discussed corrective actions with QA")
        let hits = SearchEngine.search("corrective", scope: .all, in: [inBody, inTitle], now: now)
        #expect(ids(hits) == ["title", "body"])
    }

    @Test func searchingAnEventNameFindsItsContext() {
        let docs = [
            doc("in", title: "Send agenda", event: "Vendor security review"),
            doc("out", title: "Send agenda", event: "Board prep")
        ]
        let hits = SearchEngine.search("vendor", scope: .all, in: docs, now: now)
        #expect(ids(hits) == ["in"])
        #expect(hits.first?.signals.first?.reason == .matchesEventName)
    }

    @Test func itemsOfTheRunningEventOutrankTheSameItemsOfAnOldEvent() {
        let current = doc("current", title: "Risk register", eventStart: now - 20 * 60)
        let old = doc("old", title: "Risk register", event: "Old", eventStart: now - 40 * day, createdAt: now - 40 * day)
        let hits = SearchEngine.search("risk", scope: .all, in: [old, current], now: now)
        #expect(ids(hits) == ["current", "old"])
        #expect(hits.first?.signals.contains { $0.reason == .eventHappeningNow } == true)
    }

    @Test func timeNeverRescuesAnItemThatDoesNotMatch() {
        let docs = [doc("a", title: "Completely unrelated")]
        #expect(SearchEngine.search("risk", scope: .all, in: docs, now: now).isEmpty)
    }

    @Test func scopeFiltersByKind() {
        let docs = [
            doc("task", .task, title: "Send audit log"),
            doc("note", .note, title: "Audit notes"),
            doc("link", .link, title: "Audit plan", body: "https://example.com/audit")
        ]
        #expect(ids(SearchEngine.search("audit", scope: .tasks, in: docs, now: now)) == ["task"])
        #expect(ids(SearchEngine.search("audit", scope: .links, in: docs, now: now)) == ["link"])
        #expect(Set(ids(SearchEngine.search("audit", scope: .all, in: docs, now: now))) == ["task", "note", "link"])
    }

    @Test func linkAddressesAreSearchable() {
        let docs = [doc("link", .link, title: "Guide", body: "https://iso.org/audit-preparation", event: "Weekly sync")]
        let hits = SearchEngine.search("preparation", scope: .all, in: docs, now: now)
        #expect(ids(hits) == ["link"])
        #expect(hits.first?.signals.first?.reason == .matchesLink)
    }

    @Test func thaiTextMatchesBySubstring() {
        let docs = [doc("th", title: "เตรียมประชุมตรวจสอบภายใน")]
        #expect(ids(SearchEngine.search("ประชุม", scope: .all, in: docs, now: now)) == ["th"])
    }

    @Test func emptyOrSingleLetterQueriesReturnNothing() {
        let docs = [doc("a", title: "Anything")]
        #expect(SearchEngine.search("  ", scope: .all, in: docs, now: now).isEmpty)
        #expect(SearchEngine.search("a", scope: .all, in: docs, now: now).isEmpty)
    }

    @Test func numbersOfAnyLengthAreSearchable() {
        let docs = [doc("q3", title: "Q3 vendor list")]
        #expect(ids(SearchEngine.search("q3", scope: .all, in: docs, now: now)) == ["q3"])
        #expect(ids(SearchEngine.search("3", scope: .all, in: docs, now: now)).isEmpty)
    }

    @Test func rankingIsStableForEqualScores() {
        let docs = [doc("b", title: "Same title"), doc("a", title: "Same title")]
        let first = ids(SearchEngine.search("same", scope: .all, in: docs, now: now))
        let second = ids(SearchEngine.search("same", scope: .all, in: docs.reversed(), now: now))
        #expect(first == second)
    }

    private func temporalReason(eventStart: Date, createdAt: Date = now - 30 * day) -> SearchSignal.Reason? {
        let docs = [doc("a", title: "Audit plan", eventStart: eventStart, createdAt: createdAt)]
        let hit = SearchEngine.search("audit", scope: .all, in: docs, now: now).first
        return hit?.signals.first { $0.kind == .temporal }?.reason
    }

    @Test func timeReasonsCarryTheirNumbers() {
        #expect(temporalReason(eventStart: now + 30 * 60) == .eventStartsInMinutes(30))
        #expect(temporalReason(eventStart: now + 3 * hour) == .eventStartsInHours(3))
        #expect(temporalReason(eventStart: now + 30 * hour) == .eventStartsTomorrow)
        #expect(temporalReason(eventStart: now - 3 * hour) == .eventWasEarlierToday)
        #expect(temporalReason(eventStart: now - 30 * hour) == .eventWasYesterday)
        #expect(temporalReason(eventStart: now - 4 * day) == .eventWasDaysAgo(3))
    }

    @Test func recencyReasonsCarryTheirNumbers() {
        func recent(_ createdAt: Date) -> SearchSignal.Reason? {
            let docs = [doc("a", title: "Audit plan", createdAt: createdAt)]
            return SearchEngine.search("audit", scope: .all, in: docs, now: now).first?
                .signals.first { $0.kind == .recent }?.reason
        }
        #expect(recent(now - 2 * hour) == .addedToday)
        #expect(recent(now - 30 * hour) == .addedYesterday)
        #expect(recent(now - 4 * day) == .addedDaysAgo(4))
        #expect(recent(now - 20 * day) == nil)
    }

    @Test func snippetIsCentredOnTheMatch() {
        let body = String(repeating: "filler ", count: 30) + "the corrective action log is due " + String(repeating: "tail ", count: 30)
        let hit = SearchEngine.search("corrective", scope: .all, in: [doc("a", title: "Notes", body: body)], now: now).first
        #expect(hit?.snippet.contains("corrective") == true)
        #expect(hit?.snippet.hasPrefix("…") == true)
    }

    @Test func limitIsRespected() {
        let docs = (0..<10).map { doc("d\($0)", title: "Audit item \($0)") }
        #expect(SearchEngine.search("audit", scope: .all, in: docs, now: now, limit: 3).count == 3)
    }
}

@Suite("SearchEngine.relevantNow")
struct RelevantNowTests {
    @Test func prefersTheRunningEventThenUpcomingOnes() {
        let running = doc("running", .task, title: "Prep A", eventStart: now - 20 * 60)
        let soon = doc("soon", .task, title: "Prep B", event: "Soon", eventStart: now + hour)
        let later = doc("later", .task, title: "Prep C", event: "Later", eventStart: now + 30 * hour)

        let hits = SearchEngine.relevantNow(in: [later, soon, running], now: now, limit: 3)

        #expect(ids(hits) == ["running", "soon", "later"])
    }

    @Test func ignoresDoneTasksPastEventsAndEventDocuments() {
        let docs = [
            doc("done", .task, title: "Done", isDone: true),
            doc("past", .note, title: "Past", event: "Past", eventStart: now - 3 * day),
            doc("event", .event, title: "ISO Audit Preparation"),
            doc("far", .note, title: "Far", event: "Far", eventStart: now + 10 * day),
            doc("keep", .note, title: "Keep")
        ]
        #expect(ids(SearchEngine.relevantNow(in: docs, now: now)) == ["keep"])
    }

    @Test func respectsTheLimit() {
        let docs = (0..<6).map { doc("d\($0)", title: "Item \($0)") }
        #expect(SearchEngine.relevantNow(in: docs, now: now, limit: 2).count == 2)
    }
}
