import Foundation
import Testing
@testable import TerminalAssetDomain

private let now = Date(timeIntervalSince1970: 1_800_007_200)
private let bangkok = WeatherPlace(coordinate: WeatherCoordinate(latitude: 13.7563, longitude: 100.5018), cityName: "Bangkok")

private func snapshot(
    _ condition: WeatherCondition = .partlyCloudy,
    temperature: Double = 31,
    fetchedAt: Date = now,
    city: String? = nil
) -> WeatherSnapshot {
    WeatherSnapshot(
        temperatureC: temperature, condition: condition, isDaytime: true,
        highC: 33, lowC: 26, precipitationChance: 60, cityName: city, fetchedAt: fetchedAt
    )
}

/// Counts fetches and can be told to fail, so cache behaviour is observable.
private final class CountingProvider: WeatherProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _failure: WeatherError?
    private var _snapshot: WeatherSnapshot

    init(_ snapshot: WeatherSnapshot) { _snapshot = snapshot }

    var calls: Int { lock.withLock { _calls } }
    func fail(with error: WeatherError?) { lock.withLock { _failure = error } }
    func respond(with snapshot: WeatherSnapshot) { lock.withLock { _snapshot = snapshot } }

    func fetch(at coordinate: WeatherCoordinate, now: Date) async throws -> WeatherSnapshot {
        let (failure, snapshot) = lock.withLock { () -> (WeatherError?, WeatherSnapshot) in
            _calls += 1
            return (_failure, _snapshot)
        }
        if let failure { throw failure }
        return snapshot
    }
}

@Suite("WeatherCondition")
struct WeatherConditionTests {
    @Test(arguments: [
        (0, WeatherCondition.clear), (1, .clear), (2, .partlyCloudy), (3, .cloudy), (45, .fog),
        (53, .drizzle), (63, .rain), (66, .rain), (81, .rain), (73, .snow), (86, .snow), (95, .thunderstorm)
    ])
    func wmoCodesMapToConditions(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition.fromWMO(code) == expected)
    }

    @Test func unknownCodesFallBackToCloudy() {
        #expect(WeatherCondition.fromWMO(999) == .cloudy)
        #expect(WeatherCondition.fromWMO(-1) == .cloudy)
    }
}

@Suite("WeatherCoordinate")
struct WeatherCoordinateTests {
    @Test func roundingKeepsTwoDecimals() {
        let rounded = WeatherCoordinate(latitude: 13.75634, longitude: 100.50186).rounded()
        #expect(rounded.latitude == 13.76)
        #expect(rounded.longitude == 100.5)
    }

    @Test func distanceIsRoughlyRight() {
        let a = WeatherCoordinate(latitude: 13.75, longitude: 100.5)
        let b = WeatherCoordinate(latitude: 13.84, longitude: 100.5)
        let km = a.distanceKm(to: b)
        #expect(km > 9 && km < 11)
        #expect(a.distanceKm(to: a) == 0)
    }
}

@Suite("OpenMeteo")
struct OpenMeteoTests {
    private let json = """
    {
      "latitude": 13.75, "longitude": 100.5,
      "current": {"time": "2026-09-20T10:00", "interval": 900, "temperature_2m": 31.4, "weather_code": 61, "is_day": 1},
      "hourly": {"time": ["a","b","c"], "precipitation_probability": [10, null, 70]},
      "daily": {"time": ["2026-09-20"], "temperature_2m_max": [33.2], "temperature_2m_min": [26.1]}
    }
    """

    @Test func requestUsesRoundedCoordinatesOnly() throws {
        let url = try #require(OpenMeteo.requestURL(for: WeatherCoordinate(latitude: 13.75634, longitude: 100.50186)))
        let text = url.absoluteString
        #expect(text.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        #expect(text.contains("latitude=13.76"))
        #expect(text.contains("longitude=100.5"))
        #expect(!text.contains("13.75634"))
        #expect(!text.contains("100.50186"))
    }

    @Test func responseBecomesASnapshot() throws {
        let result = try OpenMeteo.snapshot(from: Data(json.utf8), now: now, cityName: "Bangkok")
        #expect(result.temperatureC == 31.4)
        #expect(result.condition == .rain)
        #expect(result.isDaytime)
        #expect(result.highC == 33.2)
        #expect(result.lowC == 26.1)
        #expect(result.precipitationChance == 70)
        #expect(result.cityName == "Bangkok")
    }

    @Test func missingOptionalSectionsFallBackGracefully() throws {
        let minimal = """
        {"current": {"temperature_2m": 20.0, "weather_code": 0, "is_day": 0}}
        """
        let result = try OpenMeteo.snapshot(from: Data(minimal.utf8), now: now)
        #expect(result.condition == .clear)
        #expect(!result.isDaytime)
        #expect(result.highC == 20.0)
        #expect(result.precipitationChance == 0)
    }

    @Test func malformedResponseIsATypedError() {
        #expect(throws: WeatherError.invalidResponse) {
            try OpenMeteo.snapshot(from: Data("not json".utf8), now: now)
        }
        #expect(throws: WeatherError.invalidResponse) {
            try OpenMeteo.snapshot(from: Data("{}".utf8), now: now)
        }
    }
}

@Suite("WeatherService")
struct WeatherServiceTests {
    private func cacheFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("weather-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("weather.json")
    }

    @Test func aFreshCachedForecastIsReusedWithoutAskingTheNetwork() async {
        let provider = CountingProvider(snapshot())
        let service = WeatherService(provider: provider, cacheURL: nil)

        _ = await service.weather(at: bangkok, now: now)
        let second = await service.weather(at: bangkok, now: now + 10 * 60)

        #expect(provider.calls == 1)
        #expect(second.isStale == false)
        #expect(second.snapshot?.cityName == "Bangkok")
    }

    @Test func anOldForecastIsRefetched() async {
        let provider = CountingProvider(snapshot())
        let service = WeatherService(provider: provider, cacheURL: nil, freshFor: 30 * 60)

        _ = await service.weather(at: bangkok, now: now)
        provider.respond(with: snapshot(.rain, temperature: 27, fetchedAt: now + 3600))
        let later = await service.weather(at: bangkok, now: now + 3600)

        #expect(provider.calls == 2)
        #expect(later.snapshot?.condition == .rain)
    }

    @Test func offlineFallsBackToTheLastForecastAndSaysItIsStale() async {
        let provider = CountingProvider(snapshot())
        let service = WeatherService(provider: provider, cacheURL: nil)
        _ = await service.weather(at: bangkok, now: now)

        provider.fail(with: .offline)
        let result = await service.weather(at: bangkok, now: now + 3 * 3600)

        #expect(result.snapshot != nil)
        #expect(result.isStale)
        #expect(result.error == .offline)
    }

    @Test func noCacheAndAFailedFetchGivesATypedErrorNotACrash() async {
        let provider = CountingProvider(snapshot())
        provider.fail(with: .serviceUnavailable)
        let service = WeatherService(provider: provider, cacheURL: nil)

        let result = await service.weather(at: bangkok, now: now)

        #expect(result.snapshot == nil)
        #expect(result.error == .serviceUnavailable)
    }

    @Test func aForecastForAFarawayPlaceIsNotReused() async {
        let provider = CountingProvider(snapshot())
        let service = WeatherService(provider: provider, cacheURL: nil)
        _ = await service.weather(at: bangkok, now: now)

        let chiangMai = WeatherPlace(coordinate: WeatherCoordinate(latitude: 18.79, longitude: 98.98), cityName: "Chiang Mai")
        provider.fail(with: .offline)
        let result = await service.weather(at: chiangMai, now: now + 60)

        #expect(provider.calls == 2)
        #expect(result.snapshot == nil)
    }

    @Test func theForecastSurvivesARestartThroughTheDiskCache() async {
        let file = cacheFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let firstProvider = CountingProvider(snapshot(.rain, temperature: 28))
        _ = await WeatherService(provider: firstProvider, cacheURL: file).weather(at: bangkok, now: now)

        let secondProvider = CountingProvider(snapshot(.clear))
        let restarted = WeatherService(provider: secondProvider, cacheURL: file)
        let result = await restarted.weather(at: bangkok, now: now + 60)

        #expect(secondProvider.calls == 0)
        #expect(result.snapshot?.condition == .rain)
    }

    @Test func theCityNameIsKeptWhenARefreshHasNone() async {
        let provider = CountingProvider(snapshot())
        let service = WeatherService(provider: provider, cacheURL: nil, freshFor: 60)
        _ = await service.weather(at: bangkok, now: now)

        let unnamed = WeatherPlace(coordinate: bangkok.coordinate, cityName: nil)
        let result = await service.weather(at: unnamed, now: now + 3600)

        #expect(result.snapshot?.cityName == "Bangkok")
    }
}
