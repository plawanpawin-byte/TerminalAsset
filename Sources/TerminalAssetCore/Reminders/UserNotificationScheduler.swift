#if canImport(UserNotifications)
import Foundation
import TerminalAssetDomain
import UserNotifications

/// `ReminderScheduler` backed by local notifications. Everything is scheduled on the device; no push service and
/// no network are involved.
///
/// An actor, so two replans can never interleave and leave a stale plan behind. The notification objects
/// themselves are not `Sendable`, so they are created and used entirely inside `nonisolated` helpers and only plain
/// values (statuses, identifiers) cross the actor boundary.
public actor UserNotificationScheduler: ReminderScheduler {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func authorizationStatus() async -> ReminderAuthorization {
        await Self.currentStatus()
    }

    public func requestAuthorization() async throws -> ReminderAuthorization {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            throw ReminderError.schedulingFailed(reason: error.localizedDescription)
        }
        return await Self.currentStatus()
    }

    public func replaceAll(with reminders: [PrepReminder]) async throws {
        try await Self.replace(with: reminders, calendar: calendar)
    }

    // MARK: - Notification center (nothing non-Sendable leaves these)

    private nonisolated static func currentStatus() async -> ReminderAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return map(settings.authorizationStatus)
    }

    private nonisolated static func replace(with reminders: [PrepReminder], calendar: Calendar) async throws {
        let center = UNUserNotificationCenter.current()

        let pendingIDs: [String] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        // Old reminders can always be removed, even if notifications were switched off in the meantime, so they do
        // not come back if the user allows notifications again later.
        center.removePendingNotificationRequests(
            withIdentifiers: pendingIDs.filter { $0.hasPrefix(PrepReminderPlanner.idPrefix) }
        )

        guard !reminders.isEmpty else { return }
        guard await currentStatus() == .allowed else { throw ReminderError.permissionDenied }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = ReminderText.title(for: reminder)
            content.body = ReminderText.body(for: reminder)
            content.sound = .default
            content.threadIdentifier = "prep"
            content.userInfo = ["eventKey": reminder.eventKey.rawValue]

            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                throw ReminderError.schedulingFailed(reason: error.localizedDescription)
            }
        }
    }

    private nonisolated static func map(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }
}
#endif
