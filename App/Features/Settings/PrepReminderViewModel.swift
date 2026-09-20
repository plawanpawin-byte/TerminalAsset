import Foundation
import Observation
import TerminalAssetDomain

/// Turns prep reminders on and off and keeps the scheduled notifications in step with the calendar.
///
/// Online/Offline/Degraded: reminders are local notifications, so they work with no network. If the user has
/// switched notifications off for the app, the toggle stays off and explains how to change that.
@MainActor
@Observable
final class PrepReminderViewModel {
    static let enabledKey = "settings.prepReminders"

    private(set) var isEnabled: Bool
    private(set) var authorization: ReminderAuthorization = .notDetermined
    private(set) var notice: String?

    @ObservationIgnored private let scheduler: any ReminderScheduler
    @ObservationIgnored private let defaults: UserDefaults
    /// The latest events seen, so switching the toggle on can plan straight away.
    @ObservationIgnored private var events: [TimelineEvent] = []

    init(scheduler: any ReminderScheduler, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func loadStatus() async {
        authorization = await scheduler.authorizationStatus()
        // Notifications switched off in the Settings app: the reminders cannot fire, so the toggle should say so.
        if isEnabled, authorization == .denied { store(enabled: false) }
    }

    func setEnabled(_ on: Bool, now: Date = .now) async {
        notice = nil
        guard on else {
            store(enabled: false)
            await clear()
            return
        }

        var status = await scheduler.authorizationStatus()
        if status == .notDetermined {
            do {
                status = try await scheduler.requestAuthorization()
            } catch {
                notice = "Couldn't ask for notification permission. Please try again."
                return
            }
        }
        authorization = status
        guard status == .allowed else {
            store(enabled: false)
            notice = "Notifications are off for TerminalAsset. Turn them on in the Settings app to get reminders."
            return
        }
        store(enabled: true)
        await plan(now: now)
    }

    /// Called whenever the events change. Always remembers them; schedules only when reminders are on.
    func refresh(events: [TimelineEvent], now: Date = .now) async {
        self.events = events
        guard isEnabled else { return }
        await plan(now: now)
    }

    func clearNotice() { notice = nil }

    // MARK: - Private

    private func plan(now: Date) async {
        do {
            try await scheduler.replaceAll(with: PrepReminderPlanner.plan(from: events, now: now))
        } catch ReminderError.permissionDenied {
            authorization = .denied
            store(enabled: false)
            notice = "Notifications are off for TerminalAsset. Turn them on in the Settings app to get reminders."
        } catch {
            notice = "Couldn't schedule reminders. Please try again."
        }
    }

    private func clear() async {
        // Nothing to clear (or no permission to touch notifications) is not an error worth showing.
        try? await scheduler.replaceAll(with: [])
    }

    private func store(enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }
}
