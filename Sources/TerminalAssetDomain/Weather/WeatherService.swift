import Foundation

public struct WeatherResult: Sendable, Equatable {
    /// The forecast to show, or nil when there is neither a fresh nor a cached one. A nil snapshot with a nil
    /// `error` means the request was cancelled (the user left the screen): that is not a failure to report.
    public let snapshot: WeatherSnapshot?
    /// True when `snapshot` is an older cached forecast shown because a fresh one could not be fetched.
    public let isStale: Bool
    public let error: WeatherError?

    public init(snapshot: WeatherSnapshot?, isStale: Bool, error: WeatherError?) {
        self.snapshot = snapshot
        self.isStale = isStale
        self.error = error
    }
}

/// Gets a forecast for a place, reusing a recent one instead of asking the network every time.
///
/// - Online: a forecast younger than `freshFor` for the same area is reused; otherwise it is fetched.
/// - Offline or service down: the last forecast for the same area is returned, flagged as stale.
/// - Nothing cached and the fetch failed: no snapshot and a typed error. The rest of the app keeps working.
public actor WeatherService {
    private struct CacheEntry: Codable {
        let coordinate: WeatherCoordinate
        let snapshot: WeatherSnapshot
    }

    /// A cached forecast applies to anywhere within this distance.
    private static let sameAreaKm = 5.0

    private let provider: any WeatherProvider
    private let cacheURL: URL?
    private let freshFor: TimeInterval
    private var memory: CacheEntry?

    public init(provider: any WeatherProvider, cacheURL: URL?, freshFor: TimeInterval = 30 * 60) {
        self.provider = provider
        self.cacheURL = cacheURL
        self.freshFor = freshFor
    }

    public func weather(at place: WeatherPlace, now: Date = Date()) async -> WeatherResult {
        let coordinate = place.coordinate.rounded()
        let cached = cachedEntry(near: coordinate)

        if let cached, now.timeIntervalSince(cached.snapshot.fetchedAt) < freshFor {
            return WeatherResult(snapshot: cached.snapshot.withCity(place.cityName), isStale: false, error: nil)
        }

        do {
            let fresh = try await provider.fetch(at: coordinate, now: now)
                .withCity(place.cityName ?? cached?.snapshot.cityName)
            store(CacheEntry(coordinate: coordinate, snapshot: fresh))
            return WeatherResult(snapshot: fresh, isStale: false, error: nil)
        } catch is CancellationError {
            return WeatherResult(snapshot: cached?.snapshot.withCity(place.cityName), isStale: cached != nil, error: nil)
        } catch {
            let typed = (error as? WeatherError) ?? .serviceUnavailable
            if let cached {
                return WeatherResult(snapshot: cached.snapshot.withCity(place.cityName), isStale: true, error: typed)
            }
            return WeatherResult(snapshot: nil, isStale: false, error: typed)
        }
    }

    // MARK: - Cache

    private func cachedEntry(near coordinate: WeatherCoordinate) -> CacheEntry? {
        let entry = memory ?? loadFromDisk()
        guard let entry, entry.coordinate.distanceKm(to: coordinate) < Self.sameAreaKm else { return nil }
        memory = entry
        return entry
    }

    private func store(_ entry: CacheEntry) {
        memory = entry
        guard let cacheURL, let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A failed cache write only costs a refetch next time, so it is deliberately not surfaced.
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadFromDisk() -> CacheEntry? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }
}
