import Foundation
import TerminalAssetDomain

/// Wording and unit formatting for the forecast. Presentation only; the decisions (what counts as likely rain,
/// which UV band) live in the Domain module.
enum WeatherText {
    // Forecast times are read in the forecast place's zone so "6 AM" means 6 AM there.

    static func hour(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).hour())
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
    }

    static func weekday(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
    }

    static func hourLabel(_ date: Date, isFirst: Bool, in zone: TimeZone) -> String {
        isFirst ? String(localized: "Now") : hour(date, in: zone)
    }

    static func rainOutlook(_ outlook: RainOutlook, in zone: TimeZone) -> String {
        switch outlook {
        case .none:
            String(localized: "No rain expected in the next 24 hours.")
        case .expected(let date, _):
            String(localized: "Rain likely from about \(hour(date, in: zone)).")
        case .raining(_, let until?):
            String(localized: "Rain likely now, easing around \(hour(until, in: zone)).")
        case .raining(_, nil):
            String(localized: "Rain likely for the rest of the day.")
        }
    }

    /// Wind in the user's own unit (km/h or mph), whole numbers.
    static func wind(kph: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.unitOptions = []
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: kph, unit: UnitSpeed.kilometersPerHour))
    }

    static func windCaption(kph: Double) -> String {
        switch kph {
        case ..<6: String(localized: "Calm")
        case ..<20: String(localized: "Light breeze")
        case ..<39: String(localized: "Moderate wind")
        case ..<62: String(localized: "Strong wind")
        default: String(localized: "Very strong wind")
        }
    }

    static func humidityCaption(_ percent: Int) -> String {
        switch percent {
        case ..<30: String(localized: "Dry")
        case ..<60: String(localized: "Comfortable")
        case ..<80: String(localized: "Humid")
        default: String(localized: "Very humid")
        }
    }

    static func feelsLikeCaption(feelsLike: Double, actual: Double) -> String {
        let difference = feelsLike - actual
        if difference >= 2 { return String(localized: "Feels warmer than the air temperature.") }
        if difference <= -2 { return String(localized: "Feels cooler than the air temperature.") }
        return String(localized: "Similar to the air temperature.")
    }

    static func uvCaption(_ level: UVLevel) -> String {
        switch level {
        case .low: String(localized: "No protection needed.")
        case .moderate, .high: String(localized: "Sun protection recommended.")
        case .veryHigh, .extreme: String(localized: "Avoid the midday sun.")
        }
    }
}

extension WeatherCondition {
    var title: String {
        switch self {
        case .clear: String(localized: "Clear sky")
        case .partlyCloudy: String(localized: "Partly cloudy")
        case .cloudy: String(localized: "Cloudy")
        case .fog: String(localized: "Fog")
        case .drizzle: String(localized: "Drizzle")
        case .rain: String(localized: "Rain")
        case .thunderstorm: String(localized: "Thunderstorm")
        case .snow: String(localized: "Snow")
        }
    }
}

extension UVLevel {
    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .moderate: String(localized: "Moderate")
        case .high: String(localized: "High")
        case .veryHigh: String(localized: "Very high")
        case .extreme: String(localized: "Extreme")
        }
    }
}
