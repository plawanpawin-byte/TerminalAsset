import Foundation
import TerminalAssetCore
import TerminalAssetDomain

struct BootstrapFailure: Error {
    let message: String
}

/// Composition root: the only place that knows which concrete repository and store back the app.
@MainActor
enum AppBootstrap {
    static func make() -> Result<TodayViewModel, BootstrapFailure> {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sampleData") {
                return .success(try makeSampleModel())
            }
            #endif
            let container = try TemporalStore.makeContainer()
            let sync = CalendarSyncService(
                repository: EventKitRepository(),
                store: CalendarSyncActor(modelContainer: container)
            )
            let model = TodayViewModel(sync: sync, store: ContextStore(modelContainer: container))
            return .success(model)
        } catch {
            return .failure(BootstrapFailure(message: "The local data store could not be opened on this device."))
        }
    }

    #if DEBUG
    /// In-memory database, stub calendar and seeded context. Used by previews and `-sampleData` launches.
    static func makeSampleModel(now: Date = SampleData.launchTime) throws -> TodayViewModel {
        let container = try TemporalStore.makeContainer(inMemory: true)
        let sync = CalendarSyncService(
            repository: StubCalendarRepository(snapshots: SampleData.snapshots(now: now)),
            store: CalendarSyncActor(modelContainer: container)
        )
        let store = ContextStore(modelContainer: container)
        return TodayViewModel(sync: sync, store: store) {
            await SampleData.seed(sync: sync, store: store, now: now)
        }
    }
    #endif
}
