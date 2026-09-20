import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

@MainActor
@Observable
final class CalendarViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case month
        case day

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: String(localized: "Month")
            case .day: String(localized: "Day")
            }
        }
    }

    var mode: Mode
    private(set) var displayedMonth: Date
    private(set) var selectedDay: Date
    private(set) var events: [TimelineEvent] = []
    private(set) var problem: String?

    let calendar: Calendar

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private var loadedRange: DateInterval?
    /// Identifies the latest load. Two loads can overlap (tapping Next month twice); only the newest may publish.
    @ObservationIgnored private var loadGeneration = 0

    init(
        sync: CalendarSyncService,
        store: ContextStore,
        mode: Mode = .month,
        calendar: Calendar = .current,
        today: Date = .now
    ) {
        self.sync = sync
        self.store = store
        self.mode = mode
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: today)
        self.displayedMonth = MonthGrid.startOfMonth(today, calendar: calendar)
    }

    // MARK: - Derived data

    func weeks(today: Date) -> [[CalendarDay]] {
        MonthGrid.weeks(containing: displayedMonth, calendar: calendar, today: today)
    }

    var weekdayHeaders: [String] {
        MonthGrid.weekdayHeaders(calendar: calendar)
    }

    var eventCounts: [Date: Int] {
        CalendarEvents.counts(for: events, calendar: calendar)
    }

    var agenda: [TimelineEvent] {
        CalendarEvents.events(on: selectedDay, in: events, calendar: calendar)
    }

    var allDayEvents: [TimelineEvent] {
        agenda.filter(\.isAllDay)
    }

    var positionedEvents: [PositionedEvent] {
        DayLayout.layout(events: events, on: selectedDay, calendar: calendar)
    }

    // MARK: - Actions

    func onAppear() async {
        await ensureLoaded(around: selectedDay)
    }

    /// Re-reads what is stored for the months already loaded (no calendar access), for when something changed
    /// underneath: a task added on an event, or a sync that picked up a change made in the Calendar app.
    func refreshStored() async {
        guard let loadedRange else { return }
        do {
            events = try await store.events(from: loadedRange.start, to: loadedRange.end)
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }

    func select(_ day: Date) async {
        selectedDay = calendar.startOfDay(for: day)
        displayedMonth = MonthGrid.startOfMonth(day, calendar: calendar)
        await ensureLoaded(around: day)
    }

    /// Called after an event was added: forgets what was loaded so the new event is read, and shows its day.
    func eventAdded(on day: Date) async {
        loadedRange = nil
        await select(day)
    }

    func goToToday(now: Date = .now) async {
        await select(now)
    }

    func shiftMonth(_ delta: Int) async {
        displayedMonth = MonthGrid.month(byAdding: delta, to: displayedMonth, calendar: calendar)
        // Keep the selection inside the visible month, on the same day number when it exists.
        let day = calendar.component(.day, from: selectedDay)
        let length = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 28
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        components.day = min(day, length)
        selectedDay = calendar.date(from: components).map(calendar.startOfDay(for:)) ?? displayedMonth
        await ensureLoaded(around: displayedMonth)
    }

    func shiftDay(_ delta: Int) async {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDay) else { return }
        await select(next)
    }

    // MARK: - Loading

    /// Loads a window of three months around `date`, asking the calendar for anything not synced yet.
    /// Events already stored are shown even when the calendar itself cannot be read (local first).
    private func ensureLoaded(around date: Date) async {
        let monthStart = MonthGrid.startOfMonth(date, calendar: calendar)
        let monthEnd = MonthGrid.month(byAdding: 1, to: monthStart, calendar: calendar)
        if let loadedRange, loadedRange.start <= monthStart, loadedRange.end >= monthEnd {
            // Already loaded, but returning from an event detail may have changed its context.
            await refreshStored()
            return
        }

        loadGeneration += 1
        let generation = loadGeneration

        let start = MonthGrid.month(byAdding: -1, to: monthStart, calendar: calendar)
        let end = MonthGrid.month(byAdding: 2, to: monthStart, calendar: calendar)
        let window = DateInterval(start: start, end: end)

        problem = nil
        do {
            try await sync.sync(window: window)
        } catch {
            problem = TodayViewModel.message(for: error)
        }
        do {
            let loaded = try await store.events(from: start, to: end)
            // A newer load started while this one was waiting: its result is the one that matches what is on screen.
            guard generation == loadGeneration else { return }
            events = loaded
            loadedRange = window
        } catch {
            problem = TodayViewModel.message(for: error)
        }
    }
}
