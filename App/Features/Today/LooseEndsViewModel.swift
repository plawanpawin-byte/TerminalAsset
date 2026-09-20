import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

/// Powers "Loose ends" on Today: events from earlier days that still have open tasks. It reads further back than
/// Today's own two-day window (60 days) and stays local-first: a failed calendar refresh keeps whatever is already
/// stored on the device.
@MainActor
@Observable
final class LooseEndsViewModel {
    private(set) var events: [TimelineEvent] = []
    private(set) var problem: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let calendar: Calendar

    /// How far back it looks.
    private let pastDays = 60

    init(sync: CalendarSyncService, store: ContextStore, calendar: Calendar = .current) {
        self.sync = sync
        self.store = store
        self.calendar = calendar
    }

    func load(now: Date = .now) async {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -pastDays, to: today) ?? today
        let window = DateInterval(start: start, end: max(start, today))

        do {
            try await sync.sync(window: window)
        } catch {
            // Local-first: keep whatever is stored even if the calendar can't be read right now.
            problem = TodayViewModel.message(for: error)
        }
        do {
            let stored = try await store.events(from: start, to: today)
            events = LooseEnds.make(from: stored, now: now, calendar: calendar)
            if sync.authorizationStatus() == .fullAccess { problem = nil }
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }
}
