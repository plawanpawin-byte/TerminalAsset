import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class AssistantViewModel {
    private(set) var days: [HistoryDay] = []
    /// Deterministic "what needs attention" summary shown above the history.
    private(set) var briefing = AssistantBriefing(upNext: nil, looseEnds: [])
    private(set) var isLoading = true
    /// Set when a refresh failed but previously loaded history is still shown.
    private(set) var problem: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let calendar: Calendar

    /// How far back and forward the history feed reaches.
    private let pastDays = 180
    private let futureDays = 60

    init(sync: CalendarSyncService, store: ContextStore, calendar: Calendar = .current) {
        self.sync = sync
        self.store = store
        self.calendar = calendar
    }

    /// Shows what is already stored first (local-first), then widens the calendar sync to fill the history.
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
            days = CalendarHistory.days(from: events, calendar: calendar)
            briefing = AssistantBriefing.make(from: events, now: now)
            if sync.authorizationStatus() == .fullAccess { problem = nil }
        } catch {
            problem = TodayViewModel.message(for: error)
        }
        isLoading = false
    }
}
