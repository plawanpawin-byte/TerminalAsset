#if canImport(SwiftData)
import Foundation
import SwiftData

/// The first shipped shape of the database. A later release that changes a model adds `TemporalSchemaV2` next to
/// this one and a migration stage in `TemporalMigrationPlan`, instead of rewriting this type: users keep their
/// context across updates. Never edit a released schema in place.
public enum TemporalSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [TemporalEvent.self, TemporalContext.self, ContextItem.self, InboxEntry.self]
    }
}

public enum TemporalMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [TemporalSchemaV1.self] }

    /// Nothing to migrate yet: V1 is the only version.
    public static var stages: [MigrationStage] { [] }
}

public enum TemporalStore {
    /// `Schema` is not `Sendable`, so a fresh instance is built per use instead of sharing a static.
    public static func makeSchema() -> Schema {
        Schema(versionedSchema: TemporalSchemaV1.self)
    }

    /// Builds the app's container. Pass `inMemory: true` for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: TemporalMigrationPlan.self, configurations: [configuration])
    }
}
#endif
