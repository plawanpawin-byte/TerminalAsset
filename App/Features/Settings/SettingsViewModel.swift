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
    /// The language the user picked for this app (iOS applies it the next time the app opens).
    private(set) var language: AppLanguage
    /// A short result or failure to show in an alert.
    private(set) var notice: String?

    @ObservationIgnored private let sync: CalendarSyncService
    @ObservationIgnored private let store: ContextStore
    @ObservationIgnored private let shared: SharedInbox?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let languagePreference: LanguagePreference
    @ObservationIgnored private let onDataChanged: @MainActor () async -> Void

    init(
        sync: CalendarSyncService,
        store: ContextStore,
        shared: SharedInbox?,
        calendar: Calendar = .current,
        languagePreference: LanguagePreference = LanguagePreference(),
        onDataChanged: @escaping @MainActor () async -> Void
    ) {
        self.sync = sync
        self.store = store
        self.shared = shared
        self.calendar = calendar
        self.languagePreference = languagePreference
        self.language = languagePreference.current
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
            notice = String(localized: "Couldn't prepare your data. Please try again.")
            return nil
        }
    }

    func exportFinished(_ result: Result<URL, Error>) {
        if case .failure = result { notice = String(localized: "Couldn't save the file. Please try again.") }
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
            notice = String(localized: "All data was deleted from this device. Your calendar was not changed, so its events will appear again without notes, links or tasks.")
        } catch {
            notice = String(localized: "Couldn't delete everything. Please try again.")
        }
    }

    /// Saves the language choice. Returns whether it changed, so the screen knows to tell the user to reopen the app.
    @discardableResult
    func chooseLanguage(_ new: AppLanguage) -> Bool {
        guard new != language else { return false }
        languagePreference.choose(new)
        language = new
        return true
    }

    func clearNotice() { notice = nil }
}

extension CalendarAuthorization {
    var settingsTitle: String {
        switch self {
        case .fullAccess: String(localized: "Full access")
        case .writeOnly: String(localized: "Add events only")
        case .denied: String(localized: "Off")
        case .restricted: String(localized: "Restricted")
        case .notDetermined: String(localized: "Not asked yet")
        }
    }

    var settingsExplanation: String {
        switch self {
        case .fullAccess:
            String(localized: "TerminalAsset reads your calendar on this device to show the context you need, and adds events when you create them. Your calendar is never uploaded.")
        case .writeOnly:
            String(localized: "TerminalAsset can add events but can't read them, so Today and Search stay empty. Allow full access in Settings.")
        case .denied:
            String(localized: "Calendar access is off, so TerminalAsset can't show your day. Turn it on in the Settings app.")
        case .restricted:
            String(localized: "Calendar access is restricted on this device, for example by Screen Time or a device profile.")
        case .notDetermined:
            String(localized: "Allow access so TerminalAsset can show your events. Your calendar stays on this device.")
        }
    }
}
