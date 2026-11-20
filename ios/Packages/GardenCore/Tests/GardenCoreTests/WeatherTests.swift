import XCTest
@testable import GardenCore

final class WeatherTests: XCTestCase {
    /// Trimmed Open-Meteo response in its default (metric) units.
    static let sample = """
    {"latitude":41.875,"longitude":-87.625,"generationtime_ms":0.5,"utc_offset_seconds":-18000,"timezone":"America/Chicago",
     "timezone_abbreviation":"GMT-5","elevation":181.0,
     "current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","relative_humidity_2m":"%","precipitation":"mm","wind_speed_10m":"km/h","weather_code":"wmo code"},
     "current":{"time":"2026-07-14T09:00","interval":900,"temperature_2m":25.0,"relative_humidity_2m":60,"precipitation":0.0,"wind_speed_10m":16.1,"weather_code":1},
     "hourly_units":{"time":"iso8601","temperature_2m":"°C","relative_humidity_2m":"%","precipitation_probability":"%","wind_speed_10m":"km/h"},
     "hourly":{"time":["2026-07-14T07:00","2026-07-14T08:00","2026-07-14T09:00","2026-07-14T10:00"],
               "temperature_2m":[18.0,20.0,25.0,null],"relative_humidity_2m":[75,70,60,55],
               "precipitation_probability":[0,0,10,20],"wind_speed_10m":[5.0,8.0,16.1,10.0]},
     "daily_units":{"time":"iso8601","temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_sum":"mm","precipitation_probability_max":"%",
                    "et0_fao_evapotranspiration":"mm","wind_speed_10m_max":"km/h","wind_gusts_10m_max":"km/h","weather_code":"wmo code"},
     "daily":{"time":["2026-07-13","2026-07-14"],"temperature_2m_max":[30.0,32.0],"temperature_2m_min":[20.0,null],
              "precipitation_sum":[25.4,0.0],"precipitation_probability_max":[null,40],"et0_fao_evapotranspiration":[5.08,6.35],
              "wind_speed_10m_max":[16.0934,20.0],"wind_gusts_10m_max":[40.2335,30.0],"weather_code":[61,1]}}
    """

    func testParsesAndConvertsToUSUnits() throws {
        let fetchedAt = Fixtures.at(0, 9)
        let report = try OpenMeteo.parse(Data(Self.sample.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(report.timeZoneID, "America/Chicago")
        XCTAssertEqual(report.days.count, 2)

        let d0 = report.days[0]
        XCTAssertEqual(d0.day.string, "2026-07-13")
        XCTAssertEqual(d0.highF!, 86, accuracy: 0.01)
        XCTAssertEqual(d0.lowF!, 68, accuracy: 0.01)
        XCTAssertEqual(d0.rainInches!, 1.0, accuracy: 0.001)
        XCTAssertNil(d0.rainChance)
        XCTAssertEqual(d0.et0Inches!, 0.2, accuracy: 0.001)
        XCTAssertEqual(d0.windMaxMph!, 10, accuracy: 0.01)
        XCTAssertEqual(d0.gustMaxMph!, 25, accuracy: 0.01)
        XCTAssertEqual(d0.weatherCode, 61)

        let d1 = report.days[1]
        XCTAssertEqual(d1.highF!, 89.6, accuracy: 0.01)
        XCTAssertNil(d1.lowF)
        XCTAssertEqual(d1.rainChance, 40)
        XCTAssertEqual(d1.et0Inches!, 0.25, accuracy: 0.001)

        // 7:00 is more than an hour before the fetch, so it's dropped.
        XCTAssertEqual(report.hours.count, 3)
        XCTAssertEqual(report.hours[0].time, Fixtures.at(0, 8))
        XCTAssertEqual(report.hours[0].tempF!, 68, accuracy: 0.01)
        XCTAssertNil(report.hours[2].tempF)
        XCTAssertEqual(report.hours[2].rainChance, 20)

        let current = try XCTUnwrap(report.current)
        XCTAssertEqual(current.time, Fixtures.at(0, 9))
        XCTAssertEqual(current.tempF!, 77, accuracy: 0.01)
        XCTAssertEqual(current.windMph!, 10.0, accuracy: 0.01)
        XCTAssertEqual(report.day(Fixtures.today)?.highF ?? 0, 89.6, accuracy: 0.01)
    }

    func testAPIErrorAndBadJSON() {
        XCTAssertThrowsError(try OpenMeteo.parse(Data(#"{"error":true,"reason":"Latitude must be in range of -90 to 90°."}"#.utf8))) { error in
            XCTAssertEqual(error as? OpenMeteo.ParseError, .apiError("Latitude must be in range of -90 to 90°."))
        }
        XCTAssertThrowsError(try OpenMeteo.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? OpenMeteo.ParseError, .badJSON)
        }
    }

    func testForecastURL() throws {
        let url = OpenMeteo.forecastURL(latitude: 41.8781, longitude: -87.6298, pastDays: 200)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(value("latitude"), "41.8781")
        XCTAssertEqual(value("past_days"), "92")
        XCTAssertEqual(value("timezone"), "auto")
        XCTAssertTrue(value("daily")?.contains("et0_fao_evapotranspiration") ?? false)
        // Metric on purpose: the parser converts, so units are never ambiguous.
        XCTAssertNil(value("temperature_unit"))
    }

    func testMergingKeepsHistoryAndPrefersNewer() {
        let old = Fixtures.weather(past: 10, future: 0, high: 70)
        let newer = Fixtures.weather(past: 2, future: 3, high: 90)
        let merged = old.merging(newer)
        XCTAssertEqual(merged.days.count, 14)
        XCTAssertEqual(merged.day(Fixtures.day(-5))?.highF, 70)
        XCTAssertEqual(merged.day(Fixtures.day(-1))?.highF, 90)
        XCTAssertEqual(merged.day(Fixtures.day(3))?.highF, 90)
        let trimmed = old.merging(newer, keepDays: 5)
        XCTAssertEqual(trimmed.days.first?.day, Fixtures.day(-2))
    }

    func testUnits() {
        XCTAssertEqual(Units.fahrenheit(0, unit: "°C"), 32)
        XCTAssertEqual(Units.fahrenheit(50, unit: "°F"), 50)
        XCTAssertEqual(Units.fahrenheit(100, unit: nil), 212)
        XCTAssertEqual(Units.inches(25.4, unit: "mm")!, 1, accuracy: 1e-9)
        XCTAssertEqual(Units.inches(2, unit: "inch"), 2)
        XCTAssertEqual(Units.mph(10, unit: "mph"), 10)
        XCTAssertEqual(Units.mph(10, unit: "m/s")!, 22.3694, accuracy: 1e-4)
        XCTAssertNil(Units.mph(nil, unit: "km/h"))
    }

    func testWeatherCodes() {
        XCTAssertEqual(OpenMeteo.describe(code: 0), "Clear")
        XCTAssertEqual(OpenMeteo.describe(code: 95), "Thunderstorms")
        XCTAssertEqual(OpenMeteo.describe(code: nil), "")
        XCTAssertEqual(OpenMeteo.symbol(code: 63), "cloud.rain.fill")
    }
}
