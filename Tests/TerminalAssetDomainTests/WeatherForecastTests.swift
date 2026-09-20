import Foundation
import Testing
@testable import TerminalAssetDomain

private let now = Date(timeIntervalSince1970: 1_800_007_200)

private func hour(_ offset: Int, chance: Int, condition: WeatherCondition = .cloudy) -> HourlyForecast {
    HourlyForecast(
        date: now.addingTimeInterval(TimeInterval(offset) * 3_600),
        temperatureC: 30, condition: condition, isDaytime: true, precipitationChance: chance
    )
}

private func snapshot(hours: [HourlyForecast]) -> WeatherSnapshot {
    WeatherSnapshot(
        temperatureC: 30, condition: .cloudy, isDaytime: true, highC: 33, lowC: 26,
        precipitationChance: 0, cityName: nil, fetchedAt: now, hourly: hours
    )
}

@Suite("OpenMeteo forecast detail")
struct OpenMeteoForecastTests {
    private let json = """
    {
      "current": {"time": 1800007200, "temperature_2m": 31.4, "weather_code": 3, "is_day": 1,
                  "apparent_temperature": 36.2, "relative_humidity_2m": 74.0, "wind_speed_10m": 12.5},
      "hourly": {
        "time": [1800003600, 1800007200, 1800010800],
        "temperature_2m": [30.0, 31.4, null],
        "weather_code": [3, 3, 61],
        "is_day": [1, 1, 1],
        "precipitation_probability": [10, 20, 80]
      },
      "daily": {
        "time": [1799942400, 1800028800],
        "weather_code": [61, 2],
        "temperature_2m_max": [33.2, 34.0],
        "temperature_2m_min": [26.1, 25.0],
        "precipitation_probability_max": [80, 30],
        "sunrise": [1799964000, 1800050400],
        "sunset": [1800007000, 1800093400],
        "uv_index_max": [9.4, 7.0]
      }
    }
    """

    @Test func requestAsksForUnixTimestampsAndAWeek() throws {
        let url = try #require(OpenMeteo.requestURL(for: WeatherCoordinate(latitude: 13.75, longitude: 100.5)))
        #expect(url.absoluteString.contains("timeformat=unixtime"))
        #expect(url.absoluteString.contains("forecast_days=7"))
    }

    @Test func hourlyRowsSkipHoursWithoutATemperature() throws {
        let result = try OpenMeteo.snapshot(from: Data(json.utf8), now: now)
        #expect(result.hourly.count == 2)
        #expect(result.hourly.first?.date == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(result.hourly.last?.precipitationChance == 20)
    }

    @Test func dailyRowsCarryHighLowAndCondition() throws {
        let result = try OpenMeteo.snapshot(from: Data(json.utf8), now: now)
        #expect(result.daily.count == 2)
        #expect(result.daily[0].condition == .rain)
        #expect(result.daily[0].highC == 33.2)
        #expect(result.daily[1].lowC == 25.0)
        #expect(result.daily[1].precipitationChance == 30)
    }

    @Test func detailsComeFromCurrentConditionsAndToday() throws {
        let result = try OpenMeteo.snapshot(from: Data(json.utf8), now: now)
        let details = try #require(result.details)
        #expect(details.feelsLikeC == 36.2)
        #expect(details.humidity == 74)
        #expect(details.windKph == 12.5)
        #expect(details.uvIndex == 9.4)
        #expect(details.sunrise == Date(timeIntervalSince1970: 1_799_964_000))
        #expect(details.sunset == Date(timeIntervalSince1970: 1_800_007_000))
    }

    @Test func rainChanceCoversTheHourlyRowsShown() throws {
        let result = try OpenMeteo.snapshot(from: Data(json.utf8), now: now)
        // The 80% hour has no temperature, so it is not a forecast row; the two rows shown peak at 20%.
        #expect(result.precipitationChance == 20)
    }

    @Test func aResponseWithoutForecastSectionsStillGivesCurrentConditions() throws {
        let minimal = """
        {"current": {"temperature_2m": 20.0, "weather_code": 0, "is_day": 1}}
        """
        let result = try OpenMeteo.snapshot(from: Data(minimal.utf8), now: now)
        #expect(result.hourly.isEmpty)
        #expect(result.daily.isEmpty)
        #expect(result.details == nil)
    }

    @Test func aBrokenOptionalSectionDoesNotRejectTheResponse() throws {
        let odd = """
        {"current": {"temperature_2m": 20.0, "weather_code": 0, "is_day": 1},
         "hourly": {"time": "nonsense"}, "daily": 7}
        """
        let result = try OpenMeteo.snapshot(from: Data(odd.utf8), now: now)
        #expect(result.temperatureC == 20.0)
        #expect(result.hourly.isEmpty)
    }

    @Test func aForecastCachedBeforeTheseFieldsExistedStillDecodes() throws {
        let old = """
        {"temperatureC": 30, "condition": "rain", "isDaytime": true, "highC": 33, "lowC": 26,
         "precipitationChance": 60, "cityName": "Bangkok", "fetchedAt": 800000000}
        """
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(old.utf8))
        #expect(decoded.condition == .rain)
        #expect(decoded.hourly.isEmpty)
        #expect(decoded.details == nil)
    }

    @Test func aSnapshotSurvivesEncodeAndDecode() throws {
        let original = snapshot(hours: [hour(0, chance: 40), hour(1, chance: 90)])
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

@Suite("Rain outlook")
struct RainOutlookTests {
    @Test func upcomingHoursStartAtTheCurrentHour() {
        let forecast = snapshot(hours: [hour(-2, chance: 0), hour(0, chance: 0), hour(1, chance: 0), hour(2, chance: 0)])
        let upcoming = forecast.upcomingHours(from: now.addingTimeInterval(20 * 60), limit: 2)
        #expect(upcoming.count == 2)
        #expect(upcoming.first?.date == now)
    }

    @Test func dryDayHasNoOutlook() {
        let forecast = snapshot(hours: (0..<12).map { hour($0, chance: 10) })
        #expect(forecast.rainOutlook(from: now) == .none)
    }

    @Test func laterRainNamesTheFirstLikelyHour() {
        let forecast = snapshot(hours: [hour(0, chance: 10), hour(1, chance: 20), hour(2, chance: 60), hour(3, chance: 90)])
        #expect(forecast.rainOutlook(from: now) == .expected(at: hour(2, chance: 60).date, chance: 60))
    }

    @Test func rainNowReportsWhenItEases() {
        let forecast = snapshot(hours: [hour(0, chance: 80), hour(1, chance: 70), hour(2, chance: 20), hour(3, chance: 90)])
        #expect(forecast.rainOutlook(from: now) == .raining(chance: 80, until: hour(2, chance: 20).date))
    }

    @Test func rainThatNeverEasesHasNoEndTime() {
        let forecast = snapshot(hours: (0..<6).map { hour($0, chance: 70) })
        #expect(forecast.rainOutlook(from: now) == .raining(chance: 70, until: nil))
    }

    @Test func noHourlyDataMeansNoOutlook() {
        #expect(snapshot(hours: []).rainOutlook(from: now) == .none)
    }
}

@Suite("UVLevel")
struct UVLevelTests {
    @Test(arguments: [
        (0.0, UVLevel.low), (2.9, .low), (3.0, .moderate), (5.9, .moderate),
        (6.0, .high), (7.9, .high), (8.0, .veryHigh), (10.9, .veryHigh), (11.0, .extreme), (14.0, .extreme)
    ])
    func indexMapsToWHOCategory(index: Double, expected: UVLevel) {
        #expect(UVLevel(index: index) == expected)
    }
}
