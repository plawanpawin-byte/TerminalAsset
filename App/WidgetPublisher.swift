import Foundation
import TerminalAssetCore
import TerminalAssetDomain
import WidgetKit

/// Writes the small snapshot the home-screen widget reads, and asks WidgetKit to redraw. The widget cannot open the
/// database or the calendar itself, so this is its only source of data.
///
/// Degraded: the widget is a convenience. If the snapshot cannot be written (for example no App Group container in
/// an unsigned build) the app carries on and the widget keeps showing the last snapshot it has.
struct WidgetPublisher: Sendable {
    /// How far ahead the widget looks for the next event.
    private static let lookahead: TimeInterval = 7 * 24 * 3600

    let store: ContextStore
    let directory: URL?

    /// Returns false when nothing could be published, so callers and tests can tell.
    @discardableResult
    func publish(now: Date = .now) async -> Bool {
        guard let directory else { return false }
        do {
            let events = try await store.events(from: now, to: now.addingTimeInterval(Self.lookahead))
            try WidgetSnapshot.make(from: events, now: now).write(to: directory)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            return false
        }
    }
}
