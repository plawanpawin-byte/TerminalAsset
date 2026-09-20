import SwiftUI
import TerminalAssetDomain

private let rainTint = Color(hex: 0x8EDBFF)

// MARK: - Hourly

/// The next 24 hours as a horizontal strip, with a one-line answer to "will it rain?" on top.
struct HourlyForecastCard: View {
    let snapshot: WeatherSnapshot
    let now: Date

    var body: some View {
        let hours = snapshot.upcomingHours(from: now)
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassHeading(text: "Hourly forecast", symbol: "clock")
                Text(WeatherText.rainOutlook(snapshot.rainOutlook(from: now), in: snapshot.timeZone))
                    .font(.subheadline)
                Divider().overlay(.white.opacity(0.25))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                            HourColumn(hour: hour, isFirst: index == 0, zone: snapshot.timeZone)
                        }
                    }
                }
            }
        }
    }
}

private struct HourColumn: View {
    let hour: HourlyForecast
    let isFirst: Bool
    let zone: TimeZone

    private var label: String { WeatherText.hourLabel(hour.date, isFirst: isFirst, in: zone) }

    private var showsRain: Bool { hour.precipitationChance >= 20 }

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
            VStack(spacing: 2) {
                Image(systemName: hour.condition.symbol(isDaytime: hour.isDaytime))
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
                    .frame(height: 26)
                Text(showsRain ? "\(hour.precipitationChance)%" : " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rainTint)
            }
            Text(TemperatureText.format(celsius: hour.temperatureC))
                .font(.headline)
        }
        .frame(minWidth: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(
            "\(TemperatureText.format(celsius: hour.temperatureC)), \(hour.condition.title)"
                + (showsRain ? ", \(hour.precipitationChance) percent chance of rain" : "")
        )
    }
}

// MARK: - Daily

struct DailyForecastCard: View {
    let snapshot: WeatherSnapshot
    let now: Date

    var body: some View {
        let days = snapshot.daily
        let low = days.map(\.lowC).min() ?? 0
        let high = days.map(\.highC).max() ?? 1
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                GlassHeading(text: "\(days.count)-day forecast", symbol: "calendar")
                    .padding(.bottom, 6)
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { Divider().overlay(.white.opacity(0.2)) }
                    DayRow(day: day, weekLow: low, weekHigh: high, isToday: snapshot.calendar.isDate(day.date, inSameDayAs: now), zone: snapshot.timeZone)
                }
            }
        }
    }
}

private struct DayRow: View {
    let day: DailyForecast
    let weekLow: Double
    let weekHigh: Double
    let isToday: Bool
    let zone: TimeZone

    private var showsRain: Bool { day.precipitationChance >= 20 }

    private var name: String {
        isToday ? "Today" : WeatherText.weekday(day.date, in: zone)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.body.weight(.medium))
                .frame(width: 58, alignment: .leading)
            VStack(spacing: 0) {
                Image(systemName: day.condition.symbol(isDaytime: true))
                    .symbolRenderingMode(.multicolor)
                    .frame(height: 22)
                Text(showsRain ? "\(day.precipitationChance)%" : " ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(rainTint)
            }
            .frame(width: 34)
            Text(TemperatureText.format(celsius: day.lowC))
                .frame(width: 38, alignment: .trailing)
                .opacity(0.7)
            RangeBar(low: day.lowC, high: day.highC, weekLow: weekLow, weekHigh: weekHigh)
                .frame(height: 5)
            Text(TemperatureText.format(celsius: day.highC))
                .frame(width: 38, alignment: .leading)
        }
        .font(.body)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(
            "\(day.condition.title), high \(TemperatureText.format(celsius: day.highC)), low \(TemperatureText.format(celsius: day.lowC))"
                + (showsRain ? ", \(day.precipitationChance) percent chance of rain" : "")
        )
    }
}

/// A day's temperature range drawn against the whole week's range.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max(weekHigh - weekLow, 1)
            let start = (low - weekLow) / span
            let end = (high - weekLow) / span
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x6EC6FF), Color(hex: 0xFFB347)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(width * (end - start), 5))
                    .offset(x: width * start)
            }
        }
    }
}

// MARK: - Detail tiles

/// Feels-like, humidity, wind, UV, sun and rain as small square tiles, like the Apple Weather app.
struct WeatherDetailsGrid: View {
    let snapshot: WeatherSnapshot
    let now: Date

    private struct Tile: Identifiable {
        let title: String
        let symbol: String
        let value: String
        let caption: String
        var id: String { title }
    }

    private var tiles: [Tile] {
        var tiles: [Tile] = []
        if let details = snapshot.details {
            if let feelsLike = details.feelsLikeC {
                tiles.append(Tile(
                    title: "Feels like", symbol: "thermometer.medium",
                    value: TemperatureText.format(celsius: feelsLike),
                    caption: WeatherText.feelsLikeCaption(feelsLike: feelsLike, actual: snapshot.temperatureC)
                ))
            }
            if let humidity = details.humidity {
                tiles.append(Tile(
                    title: "Humidity", symbol: "humidity.fill",
                    value: "\(humidity)%", caption: WeatherText.humidityCaption(humidity)
                ))
            }
            if let wind = details.windKph {
                tiles.append(Tile(
                    title: "Wind", symbol: "wind",
                    value: WeatherText.wind(kph: wind), caption: WeatherText.windCaption(kph: wind)
                ))
            }
            if let uv = details.uvIndex {
                let level = UVLevel(index: uv)
                tiles.append(Tile(
                    title: "UV index", symbol: "sun.max.fill",
                    value: "\(Int(uv.rounded())) · \(level.title)", caption: WeatherText.uvCaption(level)
                ))
            }
            if let sun = sunTile(details) { tiles.append(sun) }
        }
        tiles.append(Tile(
            title: "Rain", symbol: "umbrella.fill",
            value: "\(snapshot.precipitationChance)%", caption: "Highest chance in the next 12 hours."
        ))
        return tiles
    }

    private func sunTile(_ details: WeatherDetails) -> Tile? {
        guard let sunrise = details.sunrise, let sunset = details.sunset else { return nil }
        let zone = snapshot.timeZone
        if now < sunrise {
            return Tile(
                title: "Sunrise", symbol: "sunrise.fill",
                value: WeatherText.time(sunrise, in: zone), caption: "Sunset: \(WeatherText.time(sunset, in: zone))"
            )
        }
        return Tile(
            title: "Sunset", symbol: "sunset.fill",
            value: WeatherText.time(sunset, in: zone), caption: "Sunrise: \(WeatherText.time(sunrise, in: zone))"
        )
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(tiles) { tile in
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        GlassHeading(text: tile.title, symbol: tile.symbol)
                        Text(tile.value)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(tile.caption)
                            .font(.footnote)
                            .opacity(0.85)
                            .lineLimit(3)
                    }
                    .frame(height: 112, alignment: .topLeading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Open-Meteo asks for attribution (CC BY 4.0). Also tells the user where the numbers come from.
struct WeatherAttribution: View {
    var body: some View {
        Text("Weather data by Open-Meteo.com")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
    }
}
