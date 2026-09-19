import Foundation

/// Request building and response parsing for the Open-Meteo forecast API (https://open-meteo.com).
/// Free, no account and no API key. Only a coordinate rounded to about 1 km leaves the device.
public enum OpenMeteo {
    public static func requestURL(for coordinate: WeatherCoordinate) -> URL? {
        let rounded = coordinate.rounded()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(rounded.latitude)),
            URLQueryItem(name: "longitude", value: String(rounded.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "forecast_days", value: "1"),
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
        return WeatherSnapshot(
            temperatureC: temperature,
            condition: WeatherCondition.fromWMO(response.current.weatherCode),
            isDaytime: response.current.isDay == 1,
            highC: response.daily?.maxTemperatures.compactMap { $0 }.first ?? temperature,
            lowC: response.daily?.minTemperatures.compactMap { $0 }.first ?? temperature,
            precipitationChance: response.hourly?.precipitationProbability.compactMap { $0 }.max() ?? 0,
            cityName: cityName,
            fetchedAt: now
        )
    }

    struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let precipitationProbability: [Int?]

            enum CodingKeys: String, CodingKey {
                case precipitationProbability = "precipitation_probability"
            }
        }

        struct Daily: Decodable {
            let maxTemperatures: [Double?]
            let minTemperatures: [Double?]

            enum CodingKeys: String, CodingKey {
                case maxTemperatures = "temperature_2m_max"
                case minTemperatures = "temperature_2m_min"
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }
}
