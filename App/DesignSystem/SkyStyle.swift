import SwiftUI
import TerminalAssetDomain

extension Color {
    /// `Color(hex: 0x1E6FD9)`. sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The colours of the sky behind the Today screen. Every palette is dark enough for white text, so the text
/// on top never needs to change with the weather.
struct SkyStyle: Equatable {
    let top: Color
    let bottom: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func make(condition: WeatherCondition, isDaytime: Bool) -> SkyStyle {
        let (top, bottom): (UInt32, UInt32) = switch (condition, isDaytime) {
        case (.clear, true): (0x1E6FD9, 0x5AA9E6)
        case (.clear, false): (0x0B1D3A, 0x1F3B63)
        case (.partlyCloudy, true): (0x3F78B5, 0x86AED2)
        case (.partlyCloudy, false): (0x16233B, 0x2E4363)
        case (.cloudy, true): (0x56667A, 0x8592A2)
        case (.cloudy, false): (0x212833, 0x394252)
        case (.fog, true): (0x6F7C8A, 0x9AA4AF)
        case (.fog, false): (0x2A3038, 0x474F5A)
        case (.drizzle, true), (.rain, true): (0x3A4D62, 0x62778C)
        case (.drizzle, false), (.rain, false): (0x18202B, 0x2C3948)
        case (.thunderstorm, true): (0x2B2F3F, 0x4A4F63)
        case (.thunderstorm, false): (0x13141E, 0x2A2C3D)
        case (.snow, true): (0x6683A3, 0x9DB2C9)
        case (.snow, false): (0x2A3950, 0x54678A)
        }
        return SkyStyle(top: Color(hex: top), bottom: Color(hex: bottom))
    }
}

extension WeatherCondition {
    func symbol(isDaytime: Bool) -> String {
        switch self {
        case .clear: isDaytime ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDaytime ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snow: "cloud.snow.fill"
        }
    }
}

enum TemperatureText {
    /// "31°" in metric locales, "88°" in US ones.
    static func format(celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            ))
    }
}
