@preconcurrency import CoreLocation
import Foundation
import TerminalAssetDomain

enum LocationPermission: Equatable {
    case notDetermined
    /// Denied or restricted: the user has to change it in Settings.
    case denied
    case authorized
}

enum LocationError: Error {
    case unavailable
}

/// Where the user is, as far as the forecast needs to know. The Today screen depends on this protocol, not on
/// CoreLocation, so previews, demo mode and tests can supply a fixed place.
@MainActor
protocol LocationProviding: AnyObject {
    func permission() -> LocationPermission
    /// Shows the system prompt if the user has not been asked yet. Returns the resulting permission.
    func requestPermission() async -> LocationPermission
    func currentPlace() async throws -> WeatherPlace
}

/// Approximate, when-in-use location. A forecast does not need precision, so accuracy is set to kilometres,
/// which also lets the user choose "Approximate Location" without losing the feature.
@MainActor
final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func permission() -> LocationPermission {
        Self.map(manager.authorizationStatus)
    }

    func requestPermission() async -> LocationPermission {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        return permission()
    }

    func currentPlace() async throws -> WeatherPlace {
        let location = try await requestLocation()
        let city = await cityName(for: location)
        return WeatherPlace(
            coordinate: WeatherCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            cityName: city
        )
    }

    // MARK: - Private

    private func requestLocation() async throws -> CLLocation {
        // One request at a time: a second caller would otherwise replace the first one's continuation.
        guard locationContinuation == nil else { throw LocationError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// The place name is a nicety: without it the forecast still works, so a failed lookup returns nil.
    /// The lookup goes to Apple's geocoding service, so it gets the same ~1 km rounded position as the forecast.
    private func cityName(for location: CLLocation) async -> String? {
        let coarse = WeatherCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ).rounded()
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coarse.latitude, longitude: coarse.longitude)
            )
            let mark = placemarks.first
            return PlaceName.choose(
                locality: mark?.locality,
                subAdministrativeArea: mark?.subAdministrativeArea,
                administrativeArea: mark?.administrativeArea
            )
        } catch {
            return nil
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let decided = manager.authorizationStatus != .notDetermined
        Task { @MainActor in
            guard decided else { return }
            permissionContinuation?.resume()
            permissionContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: latest)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}

#if DEBUG
/// Fixed place and permission for previews and demo mode.
@MainActor
final class StubLocationService: LocationProviding {
    private var current: LocationPermission
    private let place: WeatherPlace

    init(permission: LocationPermission, place: WeatherPlace) {
        self.current = permission
        self.place = place
    }

    func permission() -> LocationPermission { current }

    func requestPermission() async -> LocationPermission {
        if current == .notDetermined { current = .authorized }
        return current
    }

    func currentPlace() async throws -> WeatherPlace { place }
}
#endif
