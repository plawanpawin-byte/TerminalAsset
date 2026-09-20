import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

/// Powers the "what needs your attention" section on Today: the next event to prepare for and past events
/// that still have open tasks. Loads a wider window than Today's own hero (past 60 days, next 30) so it
/// can surface real loose ends, and stays local-first — a failed calendar refresh keeps whatever was
/// already stored on device.
@MainActor
@Observable
final class BriefingViewModel {
    private(set) var briefing = AssistantBriefing(upNext: nil, looseEnds: [])
    private(set) var problem: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let calendar: Calendar

    /// How far back and forward the briefing looks.
    private let pastDays = 60
    private let futureDays = 30

    init(sync: CalendarSyncService, store: ContextStore, calendar: Calendar = .current) {
        self.sync = sync
        self.store = store
        self.calendar = calendar
    }

    func load(now: Date = .now) async {
        let start = calendar.date(byAdding: .day, value: -pastDays, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: futureDays, to: calendar.startOfDay(for: now)) ?? now
        let window = DateInterval(start: start, end: max(start, end))

        do {
            try await sync.sync(window: window)
        } catch {
            // Local-first: keep whatever is stored even if the calendar can't be read right now.
            problem = TodayViewModel.message(for: error)
        }
        do {
            let events = try await store.events(from: start, to: end)
            briefing = AssistantBriefing.make(from: events, now: now)
            if sync.authorizationStatus() == .fullAccess { problem = nil }
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }
}
