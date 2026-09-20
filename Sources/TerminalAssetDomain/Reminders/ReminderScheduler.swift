import Foundation

public enum ReminderAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case allowed
}

public enum ReminderError: Error, Sendable, Equatable {
    case permissionDenied
    case schedulingFailed(reason: String)
}

/// Abstraction over local notifications. The app depends on this, never on `UserNotifications`.
public protocol ReminderScheduler: Sendable {
    func authorizationStatus() async -> ReminderAuthorization

    /// Asks the user for permission to send notifications. Returns the resulting status.
    func requestAuthorization() async throws -> ReminderAuthorization

    /// Makes exactly `reminders` the pending prep reminders: earlier ones that are not in the list are removed, so
    /// a moved or deleted event never leaves a stale notification behind. An empty list clears them all.
    func replaceAll(with reminders: [PrepReminder]) async throws
}

/// In-memory scheduler for tests, previews and demo mode. It never shows a permission prompt or a notification.
public actor InMemoryReminderScheduler: ReminderScheduler {
    private var status: ReminderAuthorization
    private let grantsOnRequest: Bool
    public private(set) var scheduled: [PrepReminder] = []

    public init(status: ReminderAuthorization = .allowed, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    public func authorizationStatus() async -> ReminderAuthorization { status }

    public func requestAuthorization() async throws -> ReminderAuthorization {
        if status == .notDetermined { status = grantsOnRequest ? .allowed : .denied }
        return status
    }

    public func replaceAll(with reminders: [PrepReminder]) async throws {
        guard status == .allowed else { throw ReminderError.permissionDenied }
        scheduled = reminders
    }
}
