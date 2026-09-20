import Foundation
import Observation
import TerminalAssetDomain

@MainActor
@Observable
final class WeatherViewModel {
    enum State: Equatable {
        /// Turned off in Settings (or dismissed): nothing about weather is shown.
        case hidden
        case needsPermission(LocationPermission)
        case loading
        case ready(WeatherSnapshot, isStale: Bool)
        case unavailable(String)
    }

    private(set) var state: State = .hidden

    /// Settings toggle. A UI preference, so it lives in user defaults rather than the database.
    nonisolated static let enabledKey = "settings.showWeather"

    @ObservationIgnored private let location: any LocationProviding
    @ObservationIgnored private let service: WeatherService
    @ObservationIgnored private var lastRefresh: Date?

    init(location: any LocationProviding, service: WeatherService) {
        self.location = location
        self.service = service
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// The forecast being shown, or nil when there is none.
    var forecast: WeatherSnapshot? {
        guard case .ready(let snapshot, _) = state else { return nil }
        return snapshot
    }

    /// The sky palette for the current forecast, or nil when there is none to show.
    var sky: SkyStyle? {
        guard case .ready(let snapshot, _) = state else { return nil }
        return SkyStyle.make(condition: snapshot.condition, isDaytime: snapshot.isDaytime)
    }

    /// Picks the right state for the current setting and permission, refreshing when allowed.
    func reconcile() async {
        guard isEnabled else {
            state = .hidden
            return
        }
        switch location.permission() {
        case .notDetermined: state = .needsPermission(.notDetermined)
        case .denied: state = .needsPermission(.denied)
        case .authorized: await refresh()
        }
    }

    func allow() async {
        let result = await location.requestPermission()
        if result == .authorized {
            await refresh(force: true)
        } else {
            state = .needsPermission(result)
        }
    }

    /// "Not now": turns weather off until the user turns it back on in Settings.
    func dismissPrompt() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        state = .hidden
    }

    func refresh(force: Bool = false) async {
        if !force, case .ready(_, isStale: false) = state, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 600 {
            return
        }
        if case .ready = state {} else { state = .loading }

        do {
            let place = try await location.currentPlace()
            let result = await service.weather(at: place)
            if let snapshot = result.snapshot {
                state = .ready(snapshot, isStale: result.isStale)
                lastRefresh = Date()
            } else if case .ready = state {
                // Keep showing the previous forecast rather than replacing it with an error.
            } else {
                state = .unavailable(Self.message(for: result.error))
            }
        } catch {
            if case .ready = state {} else {
                state = .unavailable("Couldn't find your location. Try again in a moment.")
            }
        }
    }

    private static func message(for error: WeatherError?) -> String {
        switch error {
        case .offline: "You're offline, so the forecast isn't available."
        case .serviceUnavailable, .invalidResponse, .none: "The forecast isn't available right now."
        }
    }
}
