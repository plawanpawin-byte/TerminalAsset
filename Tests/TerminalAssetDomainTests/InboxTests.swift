import Foundation
import Testing
@testable import TerminalAssetDomain

private let hour: TimeInterval = 3600
private let minute: TimeInterval = 60
/// 2027-01-15 10:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_007_200)

private func event(
    _ title: String,
    from start: Date,
    lasting duration: TimeInterval = hour,
    allDay: Bool = false,
    state: SyncState = .active,
    itemTitles: [String] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"),
        title: title,
        startDate: start,
        endDate: start + duration,
        isAllDay: allDay,
        location: nil,
        syncState: state,
        items: itemTitles.map {
            ContextItemValue(id: UUID(), kind: .note, title: $0, detail: nil, url: nil, isDone: false, createdAt: now)
        }
    )
}

private func makeInbox() throws -> (SharedInbox, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TerminalAssetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (SharedInbox(rootURL: root), root)
}

private func tempFile(named name: String, contents: String = "hello") throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(contents.utf8).write(to: url)
    return url
}

@Suite("SharedInbox")
struct SharedInboxTests {
    @Test func enqueuedLinkCanBeReadBack() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }

        let draft = InboxDraft(kind: .url, title: "Audit guide", urlString: "https://iso.org/guide", receivedAt: now)
        let manifest = try inbox.enqueue(draft)

        let result = try inbox.pending()
        #expect(result.rejected == 0)
        #expect(result.items.map(\.manifest.id) == [manifest.id])
        #expect(result.items.first?.manifest.urlString == "https://iso.org/guide")
        #expect(result.items.first?.payloadURL == nil)
    }

    @Test func payloadFileIsCopiedNotMoved() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try tempFile(named: "Q3 vendor list.xlsx")

        try inbox.enqueue(InboxDraft(kind: .file, title: "Q3 vendor list.xlsx"), payload: source)

        #expect(FileManager.default.fileExists(atPath: source.path))
        let item = try #require(try inbox.pending().items.first)
        #expect(item.payloadURL?.lastPathComponent == "Q3 vendor list.xlsx")
    }

    @Test func fileKindWithoutPayloadIsRejected() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SharedInboxError.payloadMissing) {
            try inbox.enqueue(InboxDraft(kind: .image, title: "x"))
        }
    }

    @Test func storeAttachmentThenRemoveClearsTheQueue() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try tempFile(named: "a.png")
        let manifest = try inbox.enqueue(InboxDraft(kind: .image, title: "a.png"), payload: source)
        let item = try #require(try inbox.pending().items.first)

        let path = try #require(try inbox.storeAttachment(for: item))
        #expect(path == "\(manifest.id.uuidString)/a.png")
        #expect(FileManager.default.fileExists(atPath: inbox.attachmentURL(for: path).path))

        inbox.remove(id: manifest.id)
        #expect(try inbox.pending().items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: inbox.attachmentURL(for: path).path))
    }

    @Test func deletingAnAttachmentCanNeverReachBeyondItsOwnFile() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try tempFile(named: "a.png")
        let manifest = try inbox.enqueue(InboxDraft(kind: .image, title: "a.png"), payload: source)
        let item = try #require(try inbox.pending().items.first)
        let path = try #require(try inbox.storeAttachment(for: item))
        let stored = inbox.attachmentURL(for: path)

        // A record with a climbing path must not delete the folder above the file.
        inbox.deleteAttachment(relativePath: "\(manifest.id.uuidString)/..")
        inbox.deleteAttachment(relativePath: "..")
        inbox.deleteAttachment(relativePath: "")
        #expect(FileManager.default.fileExists(atPath: stored.path))

        inbox.deleteAttachment(relativePath: path)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
        #expect(FileManager.default.fileExists(atPath: inbox.attachmentsDirectory.path))
    }

    @Test func storingTheSameAttachmentTwiceIsHarmless() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try tempFile(named: "a.png")
        try inbox.enqueue(InboxDraft(kind: .image, title: "a.png"), payload: source)
        let item = try #require(try inbox.pending().items.first)

        let first = try inbox.storeAttachment(for: item)
        let second = try inbox.storeAttachment(for: item)
        #expect(first == second)
    }

    @Test func corruptItemIsSetAsideAndDoesNotBlockOthers() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        try inbox.enqueue(InboxDraft(kind: .text, title: "good", text: "good"))

        let broken = inbox.inboxDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appendingPathComponent("manifest.json"))

        let result = try inbox.pending()
        #expect(result.items.count == 1)
        #expect(result.rejected == 1)
        #expect(!FileManager.default.fileExists(atPath: broken.path))
        // Set aside, not retried on the next scan.
        #expect(try inbox.pending().rejected == 0)
    }

    @Test func incompleteStagingItemsAreIgnored() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = inbox.inboxDirectory.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let result = try inbox.pending()
        #expect(result.items.isEmpty)
        #expect(result.rejected == 0)
    }

    @Test func pendingItemsAreOrderedOldestFirst() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        try inbox.enqueue(InboxDraft(kind: .text, title: "later", text: "later", receivedAt: now + hour))
        try inbox.enqueue(InboxDraft(kind: .text, title: "earlier", text: "earlier", receivedAt: now))

        #expect(try inbox.pending().items.map(\.manifest.title) == ["earlier", "later"])
    }

    @Test func fileNamesAreSanitized() {
        #expect(SharedInbox.sanitizedFileName("../../etc/passwd") == "passwd")
        #expect(SharedInbox.sanitizedFileName("a:b.txt") == "a_b.txt")
        #expect(SharedInbox.sanitizedFileName("manifest.json") == "file")
        #expect(SharedInbox.sanitizedFileName("  ") == "file")
        #expect(SharedInbox.sanitizedFileName("..") == "file")
        #expect(SharedInbox.sanitizedFileName(".") == "file")
        #expect(SharedInbox.sanitizedFileName("Manifest.JSON") == "file")
    }

    @Test func aLongNameIsShortenedButKeepsItsExtension() {
        let thai = String(repeating: "ประชุม", count: 30) + ".pdf"
        let name = SharedInbox.sanitizedFileName(thai)
        #expect(name.utf8.count <= SharedInbox.maxFileNameBytes)
        #expect(name.hasSuffix(".pdf"))
        #expect(name.hasPrefix("ประชุม"))
        #expect(SharedInbox.sanitizedFileName("short.txt") == "short.txt")
    }
}

@Suite("InboxManifest")
struct InboxManifestTests {
    @Test func linkBecomesALinkItem() {
        let manifest = InboxManifest(
            id: UUID(),
            draft: InboxDraft(kind: .url, title: "Guide", urlString: "https://iso.org")
        )
        let draft = manifest.contextDraft(attachmentPath: nil)
        #expect(draft.kind == .link)
        #expect(draft.urlString == "https://iso.org")
    }

    @Test func longTextBecomesANoteWithTheFullTextAsDetail() {
        let body = "First line of the note\nSecond line with more detail"
        let manifest = InboxManifest(id: UUID(), draft: InboxDraft(kind: .text, title: "x", text: body))
        let draft = manifest.contextDraft(attachmentPath: nil)
        #expect(draft.kind == .note)
        #expect(draft.title == "First line of the note")
        #expect(draft.detail == body)
    }

    @Test func fileBecomesAFileItemPointingAtTheStoredCopy() {
        let manifest = InboxManifest(
            id: UUID(),
            draft: InboxDraft(kind: .file, title: "Budget.xlsx", payloadFileName: "Budget.xlsx")
        )
        let draft = manifest.contextDraft(attachmentPath: "id/Budget.xlsx")
        #expect(draft.kind == .file)
        #expect(draft.fileName == "id/Budget.xlsx")
        #expect(manifest.subtitle == .fileType("XLSX"))
    }

    @Test func textSubtitleDoesNotRepeatTheTitle() {
        let same = InboxManifest(id: UUID(), draft: InboxDraft(kind: .text, title: "Call Priya", text: "Call Priya"))
        #expect(same.subtitle == .text)

        let longer = InboxManifest(
            id: UUID(),
            draft: InboxDraft(kind: .text, title: "Meeting notes", text: "Discussed the audit scope and owners")
        )
        #expect(longer.subtitle == .excerpt("Discussed the audit scope and owners"))
    }

    @Test func manifestSurvivesJSONRoundTrip() throws {
        let manifest = InboxManifest(
            id: UUID(),
            draft: InboxDraft(kind: .url, title: "T", urlString: "https://a.b", intent: .upcomingEvent, receivedAt: now)
        )
        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(InboxManifest.self, from: data) == manifest)
    }
}

@Suite("EventSuggester")
struct EventSuggesterTests {
    @Test func runningEventIsSuggested() {
        let running = event("ISO Audit Preparation", from: now - 20 * minute)
        let other = event("Lunch", from: now + 5 * hour)

        let suggestion = EventSuggester.suggest(text: "anything", at: now, events: [other, running])

        #expect(suggestion?.eventTitle == "ISO Audit Preparation")
        #expect(suggestion?.reasons.contains(.happeningNow) == true)
    }

    @Test func sharedWordsOutrankAMoreDistantButUnrelatedEvent() {
        let related = event("Vendor security", from: now + 80 * minute)
        let unrelated = event("Dentist", from: now + 40 * minute)

        let suggestion = EventSuggester.suggest(
            text: "Vendor security questionnaire answers",
            at: now,
            events: [unrelated, related]
        )

        #expect(suggestion?.eventTitle == "Vendor security")
        #expect(suggestion?.reasons.contains(.similarTopic) == true)
    }

    @Test func nothingIsSuggestedWhenNoSignalIsStrongEnough() {
        let far = event("Offsite", from: now + 6 * hour)
        #expect(EventSuggester.suggest(text: "random", at: now, events: [far]) == nil)
    }

    @Test func recentlyEndedEventNeedsASecondSignalToBeSuggested() {
        let ended = event("Standup", from: now - 50 * minute, lasting: 30 * minute)

        // Having just ended is a weak signal on its own (score 0.30, below the 0.35 threshold)...
        #expect(EventSuggester.suggest(text: "notes", at: now, events: [ended]) == nil)

        // ...but together with a shared word it is enough.
        let suggestion = EventSuggester.suggest(text: "standup notes", at: now, events: [ended])
        #expect(suggestion?.eventTitle == "Standup")
        #expect(suggestion?.reasons.contains { if case .endedMinutesAgo = $0 { true } else { false } } == true)
    }

    @Test func missingAndAllDayEventsAreNeverSuggested() {
        let gone = event("Cancelled", from: now - 10 * minute, state: .missing)
        let holiday = event("Holiday", from: now - 10 * minute, lasting: 24 * hour, allDay: true)
        #expect(EventSuggester.suggest(text: "x", at: now, events: [gone, holiday]) == nil)
    }

    @Test func existingContextTitlesContributeToMatching() {
        let target = event("Weekly sync", from: now + 30 * minute, itemTitles: ["Kubernetes migration plan"])
        let suggestion = EventSuggester.suggest(text: "Kubernetes migration checklist", at: now, events: [target])
        #expect(suggestion?.reasons.contains(.similarTopic) == true)
    }

    @Test func currentIntentResolvesTheEventRunningAtTheMomentOfSharing() {
        let running = event("A", from: now - 10 * minute)
        let later = event("B", from: now + hour)
        #expect(EventSuggester.resolve(intent: .currentEvent, at: now, events: [later, running])?.title == "A")
        #expect(EventSuggester.resolve(intent: .currentEvent, at: now + 3 * hour, events: [later, running]) == nil)
    }

    @Test func upcomingIntentResolvesTheNextEventAfterTheMoment() {
        let soon = event("Soon", from: now + hour)
        let later = event("Later", from: now + 3 * hour)
        #expect(EventSuggester.resolve(intent: .upcomingEvent, at: now, events: [later, soon])?.title == "Soon")
    }

    @Test func decideIntentNeverResolvesAutomatically() {
        let running = event("A", from: now - 10 * minute)
        #expect(EventSuggester.resolve(intent: .decide, at: now, events: [running]) == nil)
    }
}
