#if canImport(SwiftData)
import Foundation
import SwiftData

public enum TemporalStore {
    /// `Schema` is not `Sendable`, so a fresh instance is built per use instead of sharing a static.
    ///
    /// Not a `VersionedSchema` yet, on purpose: a store created before a migration plan existed carries no version
    /// information, and opening it with a plan can fail at launch. The first release that changes a model has to
    /// introduce versioning together with a tested upgrade from this shape.
    public static func makeSchema() -> Schema {
        Schema([TemporalEvent.self, TemporalContext.self, ContextItem.self, InboxEntry.self])
    }

    /// Builds the app's container. Pass `inMemory: true` for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
