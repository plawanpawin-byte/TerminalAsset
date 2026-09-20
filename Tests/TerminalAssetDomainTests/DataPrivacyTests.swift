import Foundation
import Testing
@testable import TerminalAssetDomain

private let utc = TimeZone(identifier: "UTC") ?? .gmt
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}()

/// 2027-01-15 10:20 UTC.
private let now = Date(timeIntervalSince1970: 1_800_008_400)
private let hour: TimeInterval = 3600

private func item(_ kind: ContextItemKind, _ title: String, done: Bool = false, file: String? = nil) -> ContextItemValue {
    ContextItemValue(
        id: UUID(), kind: kind, title: title, detail: nil,
        url: kind == .link ? URL(string: "https://example.com/a") : nil,
        isDone: done, createdAt: now, fileName: file
    )
}

private func event(
    _ title: String,
    at start: Date = now,
    state: SyncState = .active,
    items: [ContextItemValue] = []
) -> TimelineEvent {
    TimelineEvent(
        key: EventKey(rawValue: "k-\(title)"), title: title, startDate: start, endDate: start + hour,
        isAllDay: false, location: "HQ", syncState: state, items: items
    )
}

@Suite("DataExport")
struct DataExportTests {
    @Test func onlyEventsWithContextAreExported() {
        let export = DataExport.make(
            from: [event("Empty"), event("Has note", items: [item(.note, "Remember")])],
            generatedAt: now
        )
        #expect(export.events.map(\.title) == ["Has note"])
    }

    @Test func eventsAreOrderedByStart() {
        let export = DataExport.make(
            from: [
                event("Later", at: now + 2 * hour, items: [item(.note, "b")]),
                event("Sooner", at: now, items: [item(.note, "a")])
            ],
            generatedAt: now
        )
        #expect(export.events.map(\.title) == ["Sooner", "Later"])
    }

    @Test func itemsKeepTheirDetails() throws {
        let export = DataExport.make(
            from: [event("Audit", items: [
                item(.task, "Send agenda", done: true),
                item(.link, "Plan"),
                item(.file, "Report", file: "abc/report.pdf")
            ])],
            generatedAt: now
        )
        let items = try #require(export.events.first).items
        #expect(items.map(\.kind) == ["task", "link", "file"])
        #expect(items[0].done == true)
        #expect(items[1].done == nil)
        #expect(items[1].url == "https://example.com/a")
        #expect(items[2].attachedFile == "abc/report.pdf")
    }

    @Test func missingEventsKeepTheirContextInTheExport() throws {
        let export = DataExport.make(
            from: [event("Gone", state: .missing, items: [item(.note, "Kept")])],
            generatedAt: now
        )
        #expect(try #require(export.events.first).state == "missing")
    }

    @Test func encodedJSONRoundTrips() throws {
        let export = DataExport.make(from: [event("Audit", items: [item(.note, "x")])], generatedAt: now)
        let data = try export.encoded()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(DataExport.self, from: data) == export)
    }

    @Test func encodedJSONIsHumanReadable() throws {
        let text = String(decoding: try DataExport.make(from: [], generatedAt: now).encoded(), as: UTF8.self)
        #expect(text.contains("\n"))
        #expect(text.contains("\"version\" : 1"))
    }

    @Test func fileNameCarriesTheDate() {
        #expect(DataExport.fileName(for: now, calendar: calendar) == "TerminalAsset-2027-01-15.json")
    }
}

@Suite("SharedInbox storage")
struct SharedInboxStorageTests {
    private func makeInbox() throws -> SharedInbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalAssetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SharedInbox(rootURL: root)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    @Test func sizeIsZeroWithNoAttachments() throws {
        #expect(try makeInbox().attachmentsSize() == 0)
    }

    @Test func sizeAddsUpEveryAttachmentFile() throws {
        let inbox = try makeInbox()
        try write(1000, to: inbox.attachmentsDirectory.appendingPathComponent("a/one.bin"))
        try write(2500, to: inbox.attachmentsDirectory.appendingPathComponent("b/two.bin"))
        #expect(inbox.attachmentsSize() == 3500)
    }

    @Test func eraseAllRemovesAttachmentsAndTheQueue() throws {
        let inbox = try makeInbox()
        try write(10, to: inbox.attachmentsDirectory.appendingPathComponent("a/one.bin"))
        try write(10, to: inbox.inboxDirectory.appendingPathComponent("q/manifest.json"))

        try inbox.eraseAll()

        #expect(inbox.attachmentsSize() == 0)
        #expect(!FileManager.default.fileExists(atPath: inbox.attachmentsDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: inbox.inboxDirectory.path))
    }

    @Test func eraseAllWithNothingStoredIsHarmless() throws {
        try makeInbox().eraseAll()
    }
}
