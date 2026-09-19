#if canImport(SwiftData)
import Foundation
import SwiftData

public enum TemporalStore {
    public static let schema = Schema([TemporalEvent.self, TemporalContext.self])

    /// Builds the app's container. Pass `inMemory: true` for tests and previews.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
