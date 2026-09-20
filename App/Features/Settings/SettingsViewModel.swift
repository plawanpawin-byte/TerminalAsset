import Foundation
import Observation
import TerminalAssetCore
import TerminalAssetDomain

/// What the Settings screen shows and does that is real: the calendar permission, how much space attachments use,
/// exporting the user's data and deleting all of it.
///
/// Offline/Degraded: everything here is local and needs no network. Without the App Group container (unsigned
/// build) there are simply no attachments to measure or delete.
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var calendarAccess: CalendarAuthorization
    private(set) var attachmentsBytes: Int64 = 0
    private(set) var isWorking = false
    /// A short result or failure to show in an alert.
    private(set) var notice: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let shared: SharedInbox?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let onDataChanged: @MainActor () async -> Void

    init(
        sync: CalendarSyncService,
        store: ContextStore,
        shared: SharedInbox?,
        calendar: Calendar = .current,
        onDataChanged: @escaping @MainActor () async -> Void
    ) {
        self.sync = sync
        self.store = store
        self.shared = shared
        self.calendar = calendar
        self.onDataChanged = onDataChanged
        self.calendarAccess = sync.authorizationStatus()
    }

    /// Re-reads the permission (it can change in the system Settings app) and the storage size.
    func refresh() async {
        calendarAccess = sync.authorizationStatus()
        guard let shared else {
            attachmentsBytes = 0
            return
        }
        attachmentsBytes = await Task.detached(priority: .utility) { shared.attachmentsSize() }.value
    }

    func requestCalendarAccess() async {
        do {
            calendarAccess = try await sync.requestAccessIfNeeded()
        } catch {
            notice = TodayViewModel.message(for: error)
        }
        if calendarAccess == .fullAccess { await onDataChanged() }
    }

    /// The user's data as JSON, ready for the "Save to Files" sheet. Nil (with a notice) when it could not be read.
    func makeExport(now: Date = .now) async -> ExportDocument? {
        isWorking = true
        defer { isWorking = false }
        do {
            let events = try await store.allEvents()
            let data = try DataExport.make(from: events, generatedAt: now).encoded()
            return ExportDocument(data: data, fileName: DataExport.fileName(for: now, calendar: calendar))
        } catch {
            notice = "Couldn't prepare your data. Please try again."
            return nil
        }
    }

    func exportFinished(_ result: Result<URL, Error>) {
        if case .failure = result { notice = "Couldn't save the file. Please try again." }
    }

    /// Deletes everything the app stored. Order matters: the database first, then the files it pointed to, so a
    /// failure half-way never leaves records that reference files that are gone.
    func eraseEverything() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.eraseEverything()
            try shared?.eraseAll()
            await onDataChanged()
            await refresh()
            notice = "All data was deleted from this device. Your calendar was not changed, so its events will appear again without notes, links or tasks."
        } catch {
            notice = "Couldn't delete everything. Please try again."
        }
    }

    func clearNotice() { notice = nil }
}

extension CalendarAuthorization {
    var settingsTitle: String {
        switch self {
        case .fullAccess: "Full access"
        case .writeOnly: "Add events only"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        }
    }

    var settingsExplanation: String {
        switch self {
        case .fullAccess:
            "TerminalAsset reads your calendar on this device to show the context you need, and adds events when you create them. Your calendar is never uploaded."
        case .writeOnly:
            "TerminalAsset can add events but can't read them, so Today and Search stay empty. Allow full access in Settings."
        case .denied:
            "Calendar access is off, so TerminalAsset can't show your day. Turn it on in the Settings app."
        case .restricted:
            "Calendar access is restricted on this device, for example by Screen Time or a device profile."
        case .notDetermined:
            "Allow access so TerminalAsset can show your events. Your calendar stays on this device."
        }
    }
}
