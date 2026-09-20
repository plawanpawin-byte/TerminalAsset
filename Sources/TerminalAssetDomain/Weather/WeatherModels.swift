import Foundation

public enum WeatherCondition: String, Sendable, Codable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case thunderstorm
    case snow

    public var title: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .thunderstorm: "Thunderstorm"
        case .snow: "Snow"
        }
    }

    /// Maps a WMO weather interpretation code (as used by Open-Meteo) to a condition.
    /// Unknown codes fall back to `.cloudy` rather than failing.
    public static func fromWMO(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1: .clear
        case 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .fog
        case 51, 53, 55, 56, 57: .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: .rain
        case 71, 73, 75, 77, 85, 86: .snow
        case 95, 96, 99: .thunderstorm
        default: .cloudy
        }
    }
}

public struct WeatherCoordinate: Sendable, Codable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Two decimal places is about 1 km. That is plenty for a forecast and avoids sending a precise position.
    public func rounded() -> WeatherCoordinate {
        WeatherCoordinate(
            latitude: (latitude * 100).rounded() / 100,
            longitude: (longitude * 100).rounded() / 100
        )
    }

    /// Approximate distance (equirectangular), good enough to decide whether a cached forecast still applies.
    public func distanceKm(to other: WeatherCoordinate) -> Double {
        let kmPerDegree = 111.32
        let dLat = (latitude - other.latitude) * kmPerDegree
        let meanLat = (latitude + other.latitude) / 2 * .pi / 180
        let dLon = (longitude - other.longitude) * kmPerDegree * cos(meanLat)
        return (dLat * dLat + dLon * dLon).squareRoot()
    }
}

public struct WeatherPlace: Sendable, Equatable {
    public let coordinate: WeatherCoordinate
    public let cityName: String?

    public init(coordinate: WeatherCoordinate, cityName: String?) {
        self.coordinate = coordinate
        self.cityName = cityName
    }
}

public struct WeatherSnapshot: Sendable, Codable, Equatable {
    public let temperatureC: Double
    public let condition: WeatherCondition
    public let isDaytime: Bool
    public let highC: Double
    public let lowC: Double
    /// Highest chance of precipitation (0...100) over the next several hours.
    public let precipitationChance: Int
    public let cityName: String?
    public let fetchedAt: Date
    /// Empty when the forecast came from an older cache or the service sent no hourly data.
    public let hourly: [HourlyForecast]
    public let daily: [DailyForecast]
    public let details: WeatherDetails?

    public init(
        temperatureC: Double,
        condition: WeatherCondition,
        isDaytime: Bool,
        highC: Double,
        lowC: Double,
        precipitationChance: Int,
        cityName: String?,
        fetchedAt: Date,
        hourly: [HourlyForecast] = [],
        daily: [DailyForecast] = [],
        details: WeatherDetails? = nil
    ) {
        self.temperatureC = temperatureC
        self.condition = condition
        self.isDaytime = isDaytime
        self.highC = highC
        self.lowC = lowC
        self.precipitationChance = precipitationChance
        self.cityName = cityName
        self.fetchedAt = fetchedAt
        self.hourly = hourly
        self.daily = daily
        self.details = details
    }

    /// Forecasts cached by an earlier version have no hourly, daily or detail fields, so those decode as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            temperatureC: try container.decode(Double.self, forKey: .temperatureC),
            condition: try container.decode(WeatherCondition.self, forKey: .condition),
            isDaytime: try container.decode(Bool.self, forKey: .isDaytime),
            highC: try container.decode(Double.self, forKey: .highC),
            lowC: try container.decode(Double.self, forKey: .lowC),
            precipitationChance: try container.decode(Int.self, forKey: .precipitationChance),
            cityName: try container.decodeIfPresent(String.self, forKey: .cityName),
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt),
            hourly: try container.decodeIfPresent([HourlyForecast].self, forKey: .hourly) ?? [],
            daily: try container.decodeIfPresent([DailyForecast].self, forKey: .daily) ?? [],
            details: try container.decodeIfPresent(WeatherDetails.self, forKey: .details)
        )
    }

    public func withCity(_ name: String?) -> WeatherSnapshot {
        WeatherSnapshot(
            temperatureC: temperatureC, condition: condition, isDaytime: isDaytime,
            highC: highC, lowC: lowC, precipitationChance: precipitationChance,
            cityName: name ?? cityName, fetchedAt: fetchedAt,
            hourly: hourly, daily: daily, details: details
        )
    }
}

public enum WeatherError: Error, Sendable, Equatable {
    case offline
    case serviceUnavailable
    case invalidResponse
}

public protocol WeatherProvider: Sendable {
    func fetch(at coordinate: WeatherCoordinate, now: Date) async throws -> WeatherSnapshot
}

/// A provider that returns a fixed forecast (or a fixed error). For previews, demo mode and tests.
public struct StubWeatherProvider: WeatherProvider {
    private let snapshot: WeatherSnapshot
    private let error: WeatherError?

    public init(snapshot: WeatherSnapshot, error: WeatherError? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    public func fetch(at coordinate: WeatherCoordinate, now: Date) async throws -> WeatherSnapshot {
        if let error { throw error }
        return snapshot
    }
}
