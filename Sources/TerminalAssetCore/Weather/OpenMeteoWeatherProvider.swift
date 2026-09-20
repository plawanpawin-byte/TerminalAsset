#if canImport(Darwin)
import Foundation
import TerminalAssetDomain

/// Fetches a forecast from Open-Meteo. Request building and parsing live in the Domain module so they can be tested
/// without a network; this type only performs the HTTP call and maps failures to `WeatherError`.
public struct OpenMeteoWeatherProvider: WeatherProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(at coordinate: WeatherCoordinate, now: Date) async throws -> WeatherSnapshot {
        guard let url = OpenMeteo.requestURL(for: coordinate) else { throw WeatherError.invalidResponse }
        let request = URLRequest(url: url, timeoutInterval: 10)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // Leaving the screen cancels the request; that is not an outage and must not be reported as one.
            if error.code == .cancelled, Task.isCancelled { throw CancellationError() }
            throw Self.map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WeatherError.serviceUnavailable
        }

        guard let http = response as? HTTPURLResponse else { throw WeatherError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return try OpenMeteo.snapshot(from: data, now: now)
        case 429, 500...:
            throw WeatherError.serviceUnavailable
        default:
            throw WeatherError.invalidResponse
        }
    }

    private static func map(_ error: URLError) -> WeatherError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .internationalRoamingOff:
            .offline
        default:
            .serviceUnavailable
        }
    }
}
#endif
