import Foundation

/// One hour of the forecast.
public struct HourlyForecast: Sendable, Codable, Equatable, Identifiable {
    public let date: Date
    public let temperatureC: Double
    public let condition: WeatherCondition
    public let isDaytime: Bool
    /// 0...100
    public let precipitationChance: Int

    public var id: Date { date }

    public init(date: Date, temperatureC: Double, condition: WeatherCondition, isDaytime: Bool, precipitationChance: Int) {
        self.date = date
        self.temperatureC = temperatureC
        self.condition = condition
        self.isDaytime = isDaytime
        self.precipitationChance = precipitationChance
    }
}

/// One day of the forecast. `date` is the start of that day in the forecast's own time zone.
public struct DailyForecast: Sendable, Codable, Equatable, Identifiable {
    public let date: Date
    public let highC: Double
    public let lowC: Double
    public let condition: WeatherCondition
    public let precipitationChance: Int

    public var id: Date { date }

    public init(date: Date, highC: Double, lowC: Double, condition: WeatherCondition, precipitationChance: Int) {
        self.date = date
        self.highC = highC
        self.lowC = lowC
        self.condition = condition
        self.precipitationChance = precipitationChance
    }
}

/// The extra readings shown as small tiles. Every field is optional because the service may omit any of them.
public struct WeatherDetails: Sendable, Codable, Equatable {
    public let feelsLikeC: Double?
    /// 0...100
    public let humidity: Int?
    public let windKph: Double?
    public let uvIndex: Double?
    public let sunrise: Date?
    public let sunset: Date?

    public init(
        feelsLikeC: Double? = nil,
        humidity: Int? = nil,
        windKph: Double? = nil,
        uvIndex: Double? = nil,
        sunrise: Date? = nil,
        sunset: Date? = nil
    ) {
        self.feelsLikeC = feelsLikeC
        self.humidity = humidity
        self.windKph = windKph
        self.uvIndex = uvIndex
        self.sunrise = sunrise
        self.sunset = sunset
    }

    var isEmpty: Bool {
        feelsLikeC == nil && humidity == nil && windKph == nil && uvIndex == nil && sunrise == nil && sunset == nil
    }
}

/// World Health Organization UV categories.
public enum UVLevel: Sendable, Equatable {
    case low, moderate, high, veryHigh, extreme

    public init(index: Double) {
        switch index {
        case ..<3: self = .low
        case ..<6: self = .moderate
        case ..<8: self = .high
        case ..<11: self = .veryHigh
        default: self = .extreme
        }
    }

    public var title: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .veryHigh: "Very high"
        case .extreme: "Extreme"
        }
    }
}

/// What the next day looks like for rain, in a form the UI can phrase.
public enum RainOutlook: Sendable, Equatable {
    /// Rain is likely now. `until` is the first hour it is expected to ease, when the forecast shows one.
    case raining(chance: Int, until: Date?)
    /// The first hour where rain becomes likely.
    case expected(at: Date, chance: Int)
    case none
}

extension WeatherSnapshot {
    /// A rain chance at or above this counts as "likely".
    public static let likelyRainChance = 50
    /// Below this the rain is considered to have eased.
    public static let easedRainChance = 30

    /// The zone of the forecast place, falling back to the device's when the service did not say.
    public var timeZone: TimeZone {
        utcOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }

    /// A calendar in the forecast place's zone, for deciding which day an instant falls on there.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The current hour and the following ones, at most `limit` of them.
    public func upcomingHours(from now: Date, limit: Int = 24) -> [HourlyForecast] {
        // The provider's first hour is the current one, so an hour that started up to 59 minutes ago still counts.
        let cutoff = now.addingTimeInterval(-3_600)
        return Array(hourly.filter { $0.date > cutoff }.sorted { $0.date < $1.date }.prefix(limit))
    }

    public func rainOutlook(from now: Date, hours: Int = 24) -> RainOutlook {
        let upcoming = upcomingHours(from: now, limit: hours)
        guard let first = upcoming.first else { return .none }
        if first.precipitationChance >= Self.likelyRainChance {
            let eased = upcoming.dropFirst().first { $0.precipitationChance < Self.easedRainChance }
            return .raining(chance: first.precipitationChance, until: eased?.date)
        }
        if let wet = upcoming.first(where: { $0.precipitationChance >= Self.likelyRainChance }) {
            return .expected(at: wet.date, chance: wet.precipitationChance)
        }
        return .none
    }
}
