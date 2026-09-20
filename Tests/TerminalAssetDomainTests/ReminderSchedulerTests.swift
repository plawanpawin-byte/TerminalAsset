import Foundation
import Testing
@testable import TerminalAssetDomain

private let now = Date(timeIntervalSince1970: 1_800_007_200)

private func reminder(_ name: String) -> PrepReminder {
    PrepReminder(
        id: PrepReminderPlanner.idPrefix + name,
        eventKey: EventKey(rawValue: name),
        fireDate: now + 600,
        eventTitle: name,
        minutesBefore: 10,
        preparation: .nothingAttached
    )
}

@Suite("InMemoryReminderScheduler")
struct ReminderSchedulerTests {
    @Test func replacingKeepsOnlyTheNewReminders() async throws {
        let scheduler = InMemoryReminderScheduler()
        try await scheduler.replaceAll(with: [reminder("a"), reminder("b")])
        try await scheduler.replaceAll(with: [reminder("b"), reminder("c")])
        #expect(await scheduler.scheduled.map(\.eventTitle) == ["b", "c"])
    }

    @Test func anEmptyListClearsEverything() async throws {
        let scheduler = InMemoryReminderScheduler()
        try await scheduler.replaceAll(with: [reminder("a")])
        try await scheduler.replaceAll(with: [])
        #expect(await scheduler.scheduled.isEmpty)
    }

    @Test func schedulingWithoutPermissionFails() async {
        let scheduler = InMemoryReminderScheduler(status: .denied)
        await #expect(throws: ReminderError.permissionDenied) {
            try await scheduler.replaceAll(with: [reminder("a")])
        }
    }

    @Test func requestingPermissionGrantsOrDeniesOnce() async throws {
        let granting = InMemoryReminderScheduler(status: .notDetermined, grantsOnRequest: true)
        #expect(try await granting.requestAuthorization() == .allowed)

        let refusing = InMemoryReminderScheduler(status: .notDetermined, grantsOnRequest: false)
        #expect(try await refusing.requestAuthorization() == .denied)
        // A refusal is remembered; asking again does not change it.
        #expect(try await refusing.requestAuthorization() == .denied)
    }
}
