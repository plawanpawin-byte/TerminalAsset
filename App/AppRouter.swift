import Foundation
import Observation
import TerminalAssetDomain

/// Carries "open this" requests from outside the app (a notification tap, the widget) to the screen that shows it.
/// It holds a request until a screen takes it, so a tap that launches the app cold is not lost.
@MainActor
@Observable
final class AppRouter {
    private(set) var pendingEvent: EventKey?

    func open(_ link: DeepLink) {
        switch link {
        case .event(let key): pendingEvent = key
        }
    }

    /// Called by the screen that has handled the request.
    func clearEvent() { pendingEvent = nil }
}
