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
        isFirst ? "Now" : hour(date, in: zone)
    }

    static func rainOutlook(_ outlook: RainOutlook, in zone: TimeZone) -> String {
        switch outlook {
        case .none:
            "No rain expected in the next 24 hours."
        case .expected(let date, _):
            "Rain likely from about \(hour(date, in: zone))."
        case .raining(_, let until?):
            "Rain likely now, easing around \(hour(until, in: zone))."
        case .raining(_, nil):
            "Rain likely for the rest of the day."
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
        case ..<6: "Calm"
        case ..<20: "Light breeze"
        case ..<39: "Moderate wind"
        case ..<62: "Strong wind"
        default: "Very strong wind"
        }
    }

    static func humidityCaption(_ percent: Int) -> String {
        switch percent {
        case ..<30: "Dry"
        case ..<60: "Comfortable"
        case ..<80: "Humid"
        default: "Very humid"
        }
    }

    static func feelsLikeCaption(feelsLike: Double, actual: Double) -> String {
        let difference = feelsLike - actual
        if difference >= 2 { return "Feels warmer than the air temperature." }
        if difference <= -2 { return "Feels cooler than the air temperature." }
        return "Similar to the air temperature."
    }

    static func uvCaption(_ level: UVLevel) -> String {
        switch level {
        case .low: "No protection needed."
        case .moderate, .high: "Sun protection recommended."
        case .veryHigh, .extreme: "Avoid the midday sun."
        }
    }
}
