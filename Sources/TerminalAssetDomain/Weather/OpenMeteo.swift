import Foundation

/// Request building and response parsing for the Open-Meteo forecast API (https://open-meteo.com).
/// Free, no account and no API key. Only a coordinate rounded to about 1 km leaves the device.
public enum OpenMeteo {
    /// Hours of hourly forecast requested; the rain chance shown next to the temperature covers the first `rainWindowHours`.
    static let forecastHours = 24
    static let rainWindowHours = 12
    static let forecastDays = 7

    public static func requestURL(for coordinate: WeatherCoordinate) -> URL? {
        let rounded = coordinate.rounded()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(rounded.latitude)),
            URLQueryItem(name: "longitude", value: String(rounded.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"
            ),
            URLQueryItem(name: "forecast_hours", value: String(forecastHours)),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            // Unix timestamps avoid parsing zone-less local time strings.
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components.url
    }

    public static func snapshot(from data: Data, now: Date, cityName: String? = nil) throws -> WeatherSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WeatherError.invalidResponse
        }
        let temperature = response.current.temperature
        let hourly = hourlyForecast(from: response.hourly)
        let daily = dailyForecast(from: response.daily)
        let rainChance = hourly.prefix(rainWindowHours).map(\.precipitationChance).max()
            ?? response.hourly?.precipitationProbability.compactMap { $0 }.prefix(rainWindowHours).max()
            ?? 0
        return WeatherSnapshot(
            temperatureC: temperature,
            condition: WeatherCondition.fromWMO(response.current.weatherCode),
            isDaytime: response.current.isDay == 1,
            highC: response.daily?.maxTemperatures.compactMap { $0 }.first ?? temperature,
            lowC: response.daily?.minTemperatures.compactMap { $0 }.first ?? temperature,
            precipitationChance: rainChance,
            cityName: cityName,
            fetchedAt: now,
            hourly: hourly,
            daily: daily,
            details: details(from: response)
        )
    }

    // MARK: - Mapping

    private static func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func hourlyForecast(from hourly: Response.Hourly?) -> [HourlyForecast] {
        guard let hourly else { return [] }
        return hourly.time.enumerated().compactMap { index, seconds in
            guard let temperature = hourly.temperatures.value(at: index),
                  let code = hourly.weatherCodes.value(at: index) else { return nil }
            return HourlyForecast(
                date: date(seconds),
                temperatureC: temperature,
                condition: WeatherCondition.fromWMO(code),
                isDaytime: (hourly.isDay.value(at: index) ?? 1) == 1,
                precipitationChance: hourly.precipitationProbability.value(at: index) ?? 0
            )
        }
    }

    private static func dailyForecast(from daily: Response.Daily?) -> [DailyForecast] {
        guard let daily else { return [] }
        return daily.time.enumerated().compactMap { index, seconds in
            guard let high = daily.maxTemperatures.value(at: index),
                  let low = daily.minTemperatures.value(at: index),
                  let code = daily.weatherCodes.value(at: index) else { return nil }
            return DailyForecast(
                date: date(seconds),
                highC: high,
                lowC: low,
                condition: WeatherCondition.fromWMO(code),
                precipitationChance: daily.precipitationProbabilityMax.value(at: index) ?? 0
            )
        }
    }

    private static func details(from response: Response) -> WeatherDetails? {
        let details = WeatherDetails(
            feelsLikeC: response.current.apparentTemperature,
            humidity: response.current.humidity,
            windKph: response.current.windSpeed,
            uvIndex: response.daily?.uvIndexMax.value(at: 0),
            sunrise: response.daily?.sunrise.value(at: 0).map(date),
            sunset: response.daily?.sunset.value(at: 0).map(date)
        )
        return details.isEmpty ? nil : details
    }

    // MARK: - Wire format

    struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let isDay: Int
            let apparentTemperature: Double?
            let humidity: Int?
            let windSpeed: Double?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
                case apparentTemperature = "apparent_temperature"
                case humidity = "relative_humidity_2m"
                case windSpeed = "wind_speed_10m"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                temperature = try container.decode(Double.self, forKey: .temperature)
                weatherCode = try container.decode(Int.self, forKey: .weatherCode)
                isDay = try container.decode(Int.self, forKey: .isDay)
                apparentTemperature = container.lenient(Double.self, forKey: .apparentTemperature)
                humidity = container.lenient(Double.self, forKey: .humidity).map { Int($0.rounded()) }
                windSpeed = container.lenient(Double.self, forKey: .windSpeed)
            }
        }

        /// The extra sections are decoded leniently: a missing or oddly typed optional array yields no forecast
        /// rows instead of rejecting the whole response, because the current conditions are still worth showing.
        struct Hourly: Decodable {
            let time: [Int]
            let temperatures: [Double?]
            let weatherCodes: [Int?]
            let isDay: [Int?]
            let precipitationProbability: [Int?]

            enum CodingKeys: String, CodingKey {
                case time
                case temperatures = "temperature_2m"
                case weatherCodes = "weather_code"
                case isDay = "is_day"
                case precipitationProbability = "precipitation_probability"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                time = container.lenientArray(Int.self, forKey: .time).compactMap { $0 }
                temperatures = container.lenientArray(Double.self, forKey: .temperatures)
                weatherCodes = container.lenientArray(Int.self, forKey: .weatherCodes)
                isDay = container.lenientArray(Int.self, forKey: .isDay)
                precipitationProbability = container.lenientArray(Int.self, forKey: .precipitationProbability)
            }
        }

        struct Daily: Decodable {
            let time: [Int]
            let weatherCodes: [Int?]
            let maxTemperatures: [Double?]
            let minTemperatures: [Double?]
            let precipitationProbabilityMax: [Int?]
            let sunrise: [Int?]
            let sunset: [Int?]
            let uvIndexMax: [Double?]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCodes = "weather_code"
                case maxTemperatures = "temperature_2m_max"
                case minTemperatures = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case sunrise
                case sunset
                case uvIndexMax = "uv_index_max"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                time = container.lenientArray(Int.self, forKey: .time).compactMap { $0 }
                weatherCodes = container.lenientArray(Int.self, forKey: .weatherCodes)
                maxTemperatures = container.lenientArray(Double.self, forKey: .maxTemperatures)
                minTemperatures = container.lenientArray(Double.self, forKey: .minTemperatures)
                precipitationProbabilityMax = container.lenientArray(Int.self, forKey: .precipitationProbabilityMax)
                sunrise = container.lenientArray(Int.self, forKey: .sunrise)
                sunset = container.lenientArray(Int.self, forKey: .sunset)
                uvIndexMax = container.lenientArray(Double.self, forKey: .uvIndexMax)
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            current = try container.decode(Current.self, forKey: .current)
            hourly = container.lenient(Hourly.self, forKey: .hourly)
            daily = container.lenient(Daily.self, forKey: .daily)
        }

        enum CodingKeys: String, CodingKey {
            case current, hourly, daily
        }
    }
}

private extension KeyedDecodingContainer {
    /// The value, or nil when the key is missing or has an unexpected type.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// An array whose elements may be null; empty when the key is missing or has an unexpected type.
    func lenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T?] {
        lenient([T?].self, forKey: key) ?? []
    }
}

private extension Array {
    /// Element at `index`, or nil when the array is shorter (a section the service left out).
    func value<T>(at index: Int) -> T? where Element == T? {
        indices.contains(index) ? self[index] : nil
    }
}
