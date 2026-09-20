import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

/// State and actions behind the "New Event" form. Validation lives in `NewEventDraft`; this only sequences
/// load → validate → write → notify, and turns failures into messages.
///
/// Offline/Degraded: adding an event is a local calendar write and needs no network. Without calendar access it
/// fails with a message and the form keeps what the user typed.
@MainActor
@Observable
final class AddEventViewModel: Identifiable {
    var draft: NewEventDraft
    private(set) var calendars: [CalendarInfo] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let onCreated: @MainActor (Date) async -> Void

    /// `onCreated` receives the start of the event that was just written, so callers can jump to that day.
    init(
        sync: CalendarSyncService,
        calendar: Calendar,
        day: Date,
        now: Date = .now,
        onCreated: @escaping @MainActor (Date) async -> Void
    ) {
        self.sync = sync
        self.calendar = calendar
        self.onCreated = onCreated
        self.draft = NewEventDraft.starting(on: day, now: now, calendar: calendar)
    }

    var canSave: Bool {
        !isSaving && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The earliest end the picker offers. All-day events compare whole days, so the end may share the start's day.
    var endRange: PartialRangeFrom<Date> {
        (draft.isAllDay ? calendar.startOfDay(for: draft.start) : draft.start)...
    }

    /// Fills the calendar choice, default first. If the list can't be read the form still works and the event goes
    /// to the system's default calendar.
    func loadCalendars() async {
        do {
            calendars = try await sync.writableCalendars()
            if draft.calendarID == nil { draft.calendarID = calendars.first?.id }
        } catch {
            calendars = []
        }
    }

    /// Returns true when the event was written and the form can close.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let event = try draft.validated(calendar: calendar)
            try await sync.createEvent(event)
            await onCreated(event.start)
            return true
        } catch let error as EventDraftError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = TodayViewModel.message(for: error)
        }
        return false
    }
}

extension EventDraftError {
    var userMessage: String {
        switch self {
        case .emptyTitle: "Enter a title."
        case .titleTooLong: "That title is too long. Keep it under \(NewEventDraft.maxTitleLength) characters."
        case .locationTooLong: "That location is too long. Keep it under \(NewEventDraft.maxLocationLength) characters."
        case .endNotAfterStart: "The event has to end after it starts."
        }
    }
}
