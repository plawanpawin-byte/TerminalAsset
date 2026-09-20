#if canImport(UserNotifications)
import Foundation
import TerminalAssetDomain
import UserNotifications

/// `ReminderScheduler` backed by local notifications. Everything is scheduled on the device; no push service and
/// no network are involved.
public struct UserNotificationScheduler: ReminderScheduler {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func authorizationStatus() async -> ReminderAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    public func requestAuthorization() async throws -> ReminderAuthorization {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            throw ReminderError.schedulingFailed(reason: error.localizedDescription)
        }
        return await authorizationStatus()
    }

    public func replaceAll(with reminders: [PrepReminder]) async throws {
        guard await authorizationStatus() == .allowed else { throw ReminderError.permissionDenied }
        let center = UNUserNotificationCenter.current()

        let pendingIDs: [String] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        center.removePendingNotificationRequests(
            withIdentifiers: pendingIDs.filter { $0.hasPrefix(PrepReminderPlanner.idPrefix) }
        )

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
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

    private static func map(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }
}
#endif
