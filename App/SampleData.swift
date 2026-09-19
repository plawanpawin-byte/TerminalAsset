#if DEBUG
import Foundation
import TerminalAssetCore
import TerminalAssetDomain

/// Demo content for previews and CI screenshots. Compiled out of release builds.
enum SampleData {
    private static let minute: TimeInterval = 60

    static func snapshots(now: Date, calendar: Calendar = .current) -> [CalendarEventSnapshot] {
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrowMorning = (calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday)
            .addingTimeInterval(9 * 60 * minute)
        return [
            make("standup", "Team standup", start: now - 150 * minute, minutes: 30, location: "Room 2"),
            make("audit", "ISO Audit Preparation", start: now - 25 * minute, minutes: 60, location: "Conference Room A"),
            make("vendor", "Vendor security review", start: now + 90 * minute, minutes: 60, location: "Zoom"),
            make("risk", "Risk register walkthrough", start: now + 240 * minute, minutes: 45, location: nil),
            make("allday", "Audit week", start: startOfToday, minutes: 24 * 60, location: nil, allDay: true),
            make("board", "Board prep", start: tomorrowMorning, minutes: 60, location: "HQ")
        ]
    }

    static func seed(sync: CalendarSyncService, store: ContextStore, now: Date) async {
        do {
            try await sync.syncNow(around: now)
            let audit = key("audit", now: now)
            try await add(store, audit, .task, "Confirm scope with QA lead", now: now)
            try await add(store, audit, .task, "Print risk register summary", now: now)
            let sent = try await add(store, audit, .task, "Send agenda to attendees", now: now)
            try await store.setTaskDone(id: sent.id, isDone: true)
            try await add(
                store, audit, .note, "Last time",
                detail: "Auditor asked for evidence of corrective actions from Q2.", now: now
            )
            try await add(store, audit, .link, "Audit Plan 2026", url: "example.com/audit-plan", now: now)

            let vendor = key("vendor", now: now)
            try await add(store, vendor, .task, "Review questionnaire answers", now: now)
            try await add(store, vendor, .link, "Vendor portal", url: "example.com/vendors", now: now)

            try await add(store, key("standup", now: now), .note, "Blocked on access request", now: now)
        } catch {
            // Demo data is best-effort; the app still runs with whatever was seeded.
            return
        }
    }

    // MARK: - Helpers

    private static func key(_ id: String, now: Date) -> EventKey {
        let match = snapshots(now: now).first { $0.eventIdentifier == id }
        return match.map { EventIdentity.key(for: $0) } ?? EventKey(rawValue: id)
    }

    @discardableResult
    private static func add(
        _ store: ContextStore,
        _ key: EventKey,
        _ kind: ContextItemKind,
        _ title: String,
        detail: String = "",
        url: String = "",
        now: Date
    ) async throws -> ContextItemValue {
        try await store.addItem(
            to: key,
            draft: ContextItemDraft(kind: kind, title: title, detail: detail, urlString: url),
            now: now
        )
    }

    private static func make(
        _ id: String,
        _ title: String,
        start: Date,
        minutes: Int,
        location: String?,
        allDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            eventIdentifier: id,
            externalIdentifier: "sample-\(id)",
            calendarID: "sample",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes) * 60),
            occurrenceDate: start,
            isAllDay: allDay,
            location: location,
            isRecurring: false
        )
    }
}
#endif
