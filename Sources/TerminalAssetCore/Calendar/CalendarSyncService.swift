#if canImport(SwiftData)
import Foundation
import TerminalAssetDomain

/// Orchestrates permission check → EventKit fetch → SwiftData apply. Holds no UI state and touches no MainActor.
///
/// Offline/Degraded: this slice needs no network. If calendar access is missing it throws a typed
/// `SyncError.calendar` and leaves already-stored events and their context fully readable.
public actor CalendarSyncService {
    /// Default window: recent past (for "previous related events") through the near future.
    public static let defaultWindowDays: (past: Int, future: Int) = (30, 90)

    private let repository: any CalendarRepository
    private let store: CalendarSyncActor
    private let calendar: Calendar

    public init(repository: any CalendarRepository, store: CalendarSyncActor, calendar: Calendar = .current) {
        self.repository = repository
        self.store = store
        self.calendar = calendar
    }

    /// Current permission without prompting, so the UI can explain before it asks.
    public nonisolated func authorizationStatus() -> CalendarAuthorization {
        repository.authorizationStatus()
    }

    public func requestAccessIfNeeded() async throws -> CalendarAuthorization {
        let status = repository.authorizationStatus()
        guard status == .notDetermined else { return status }
        do {
            return try await repository.requestAccess()
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
    }

    @discardableResult
    public func syncNow(around date: Date = .now) async throws -> SyncReport {
        let window = makeWindow(around: date)
        let snapshots: [CalendarEventSnapshot]
        do {
            snapshots = try await repository.events(in: window)
        } catch let error as CalendarError {
            throw SyncError.calendar(error)
        }
        return try await store.apply(snapshots: snapshots, window: window, now: date)
    }

    /// Syncs once, then again on every (coalesced) calendar change until the task is cancelled.
    /// `onSynced` fires after every successful sync; a failed sync is reported through `onFailure`
    /// and does not stop observation.
    public func keepInSync(
        onSynced: @Sendable (SyncReport) -> Void,
        onFailure: @Sendable (SyncError) -> Void
    ) async {
        await syncAndReport(onSynced: onSynced, onFailure: onFailure)
        for await _ in repository.storeChanges() {
            if Task.isCancelled { return }
            await syncAndReport(onSynced: onSynced, onFailure: onFailure)
        }
    }

    private func syncAndReport(
        onSynced: @Sendable (SyncReport) -> Void,
        onFailure: @Sendable (SyncError) -> Void
    ) async {
        do {
            onSynced(try await syncNow())
        } catch let error as SyncError {
            onFailure(error)
        } catch {
            onFailure(.persistence(reason: error.localizedDescription))
        }
    }

    private func makeWindow(around date: Date) -> DateInterval {
        let past = calendar.date(byAdding: .day, value: -Self.defaultWindowDays.past, to: date) ?? date
        let future = calendar.date(byAdding: .day, value: Self.defaultWindowDays.future, to: date) ?? date
        return DateInterval(start: past, end: future)
    }
}
#endif
