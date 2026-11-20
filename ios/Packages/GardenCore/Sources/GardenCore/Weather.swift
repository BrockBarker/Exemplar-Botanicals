import Foundation

public struct DailyWeather: Codable, Hashable, Sendable {
    public var day: LocalDay
    public var highF: Double?
    public var lowF: Double?
    public var rainInches: Double?
    /// Chance of rain, 0 to 100.
    public var rainChance: Double?
    /// Reference evapotranspiration (FAO-56 ET₀) in inches.
    public var et0Inches: Double?
    public var windMaxMph: Double?
    public var gustMaxMph: Double?
    public var weatherCode: Int?

    public init(
        day: LocalDay, highF: Double? = nil, lowF: Double? = nil, rainInches: Double? = nil, rainChance: Double? = nil,
        et0Inches: Double? = nil, windMaxMph: Double? = nil, gustMaxMph: Double? = nil, weatherCode: Int? = nil
    ) {
        self.day = day
        self.highF = highF
        self.lowF = lowF
        self.rainInches = rainInches
        self.rainChance = rainChance
        self.et0Inches = et0Inches
        self.windMaxMph = windMaxMph
        self.gustMaxMph = gustMaxMph
        self.weatherCode = weatherCode
    }

    /// Strongest wind number available (gusts when known).
    public var windForStakes: Double? { gustMaxMph ?? windMaxMph }
}

public struct HourlyWeather: Codable, Hashable, Sendable {
    public var time: Date
    public var tempF: Double?
    public var humidity: Double?
    public var rainChance: Double?
    public var windMph: Double?

    public init(time: Date, tempF: Double? = nil, humidity: Double? = nil, rainChance: Double? = nil, windMph: Double? = nil) {
        self.time = time
        self.tempF = tempF
        self.humidity = humidity
        self.rainChance = rainChance
        self.windMph = windMph
    }
}

public struct CurrentWeather: Codable, Hashable, Sendable {
    public var time: Date
    public var tempF: Double?
    public var humidity: Double?
    public var rainInches: Double?
    public var windMph: Double?
    public var weatherCode: Int?

    public init(time: Date, tempF: Double? = nil, humidity: Double? = nil, rainInches: Double? = nil, windMph: Double? = nil, weatherCode: Int? = nil) {
        self.time = time
        self.tempF = tempF
        self.humidity = humidity
        self.rainInches = rainInches
        self.windMph = windMph
        self.weatherCode = weatherCode
    }
}

/// Weather history plus forecast for the garden's location, in US units.
public struct WeatherReport: Codable, Sendable {
    public var fetchedAt: Date
    public var timeZoneID: String
    public var latitude: Double
    public var longitude: Double
    public var current: CurrentWeather?
    /// Past and forecast days, sorted, one per day.
    public var days: [DailyWeather]
    /// Upcoming hours (about 48).
    public var hours: [HourlyWeather]

    public init(
        fetchedAt: Date, timeZoneID: String, latitude: Double, longitude: Double,
        current: CurrentWeather? = nil, days: [DailyWeather], hours: [HourlyWeather] = []
    ) {
        self.fetchedAt = fetchedAt
        self.timeZoneID = timeZoneID
        self.latitude = latitude
        self.longitude = longitude
        self.current = current
        self.days = days.sorted { $0.day < $1.day }
        self.hours = hours.sorted { $0.time < $1.time }
    }

    public var calendar: Calendar { Calendar.garden(timeZoneID: timeZoneID) }

    public func day(_ day: LocalDay) -> DailyWeather? {
        days.first { $0.day == day }
    }

    /// Days from `start` through `end`, inclusive.
    public func days(from start: LocalDay, through end: LocalDay) -> [DailyWeather] {
        days.filter { $0.day >= start && $0.day <= end }
    }

    /// Combines stored history with a newer report. Newer values win for any day in both;
    /// days older than `keepDays` before the newest day are dropped.
    public func merging(_ newer: WeatherReport, keepDays: Int = 400) -> WeatherReport {
        var byDay: [LocalDay: DailyWeather] = [:]
        for d in days { byDay[d.day] = d }
        for d in newer.days { byDay[d.day] = d }
        var merged = byDay.values.sorted { $0.day < $1.day }
        if let last = merged.last?.day {
            let cutoff = last.adding(days: -keepDays, calendar: newer.calendar)
            merged = merged.filter { $0.day >= cutoff }
        }
        return WeatherReport(
            fetchedAt: newer.fetchedAt, timeZoneID: newer.timeZoneID, latitude: newer.latitude,
            longitude: newer.longitude, current: newer.current ?? current, days: merged, hours: newer.hours
        )
    }
}

/// Open-Meteo (free, no API key, US coverage). Requests metric units and converts here, so
/// the unit of every value is unambiguous.
public enum OpenMeteo {
    public static let dailyVariables = [
        "temperature_2m_max", "temperature_2m_min", "precipitation_sum", "precipitation_probability_max",
        "et0_fao_evapotranspiration", "wind_speed_10m_max", "wind_gusts_10m_max", "weather_code",
    ]
    public static let hourlyVariables = ["temperature_2m", "relative_humidity_2m", "precipitation_probability", "wind_speed_10m"]
    public static let currentVariables = ["temperature_2m", "relative_humidity_2m", "precipitation", "wind_speed_10m", "weather_code"]

    public static func forecastURL(latitude: Double, longitude: Double, pastDays: Int) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "daily", value: dailyVariables.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: hourlyVariables.joined(separator: ",")),
            URLQueryItem(name: "current", value: currentVariables.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: String(max(0, min(92, pastDays)))),
            URLQueryItem(name: "forecast_days", value: "8"),
        ]
        return components.url!
    }

    public enum ParseError: Error, Equatable {
        case badJSON
        case apiError(String)
    }

    private struct Response: Decodable {
        let latitude: Double
        let longitude: Double
        let timezone: String?
        let utc_offset_seconds: Int?
        let current_units: [String: String]?
        let current: [String: Value]?
        let hourly_units: [String: String]?
        let hourly: [String: [Value]]?
        let daily_units: [String: String]?
        let daily: [String: [Value]]?
    }

    private struct ErrorResponse: Decodable {
        let error: Bool?
        let reason: String?
    }

    /// A JSON value that is a number, a string or null.
    private enum Value: Decodable {
        case number(Double)
        case string(String)
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self = .null
            } else if let d = try? c.decode(Double.self) {
                self = .number(d)
            } else if let s = try? c.decode(String.self) {
                self = .string(s)
            } else {
                self = .null
            }
        }

        var double: Double? {
            if case let .number(d) = self { return d }
            return nil
        }

        var string: String? {
            if case let .string(s) = self { return s }
            return nil
        }
    }

    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> WeatherReport {
        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data), err.error == true {
            throw ParseError.apiError(err.reason ?? "unknown")
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw ParseError.badJSON }

        let zone = r.timezone.flatMap { TimeZone(identifier: $0) }
            ?? TimeZone(secondsFromGMT: r.utc_offset_seconds ?? 0)
            ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var days: [DailyWeather] = []
        if let daily = r.daily, let times = daily["time"] {
            let u = r.daily_units ?? [:]
            func col(_ name: String) -> [Value] { daily[name] ?? [] }
            func at(_ name: String, _ i: Int) -> Double? {
                let c = col(name)
                return i < c.count ? c[i].double : nil
            }
            for (i, t) in times.enumerated() {
                guard let s = t.string, let day = LocalDay(s) else { continue }
                days.append(DailyWeather(
                    day: day,
                    highF: Units.fahrenheit(at("temperature_2m_max", i), unit: u["temperature_2m_max"]),
                    lowF: Units.fahrenheit(at("temperature_2m_min", i), unit: u["temperature_2m_min"]),
                    rainInches: Units.inches(at("precipitation_sum", i), unit: u["precipitation_sum"]),
                    rainChance: at("precipitation_probability_max", i),
                    et0Inches: Units.inches(at("et0_fao_evapotranspiration", i), unit: u["et0_fao_evapotranspiration"]),
                    windMaxMph: Units.mph(at("wind_speed_10m_max", i), unit: u["wind_speed_10m_max"]),
                    gustMaxMph: Units.mph(at("wind_gusts_10m_max", i), unit: u["wind_gusts_10m_max"]),
                    weatherCode: at("weather_code", i).map { Int($0) }
                ))
            }
        }

        var hours: [HourlyWeather] = []
        if let hourly = r.hourly, let times = hourly["time"] {
            let u = r.hourly_units ?? [:]
            func at(_ name: String, _ i: Int) -> Double? {
                let c = hourly[name] ?? []
                return i < c.count ? c[i].double : nil
            }
            let earliest = fetchedAt.addingTimeInterval(-3600)
            let latest = fetchedAt.addingTimeInterval(49 * 3600)
            for (i, t) in times.enumerated() {
                guard let s = t.string, let time = localTime(s, calendar: calendar), time >= earliest, time <= latest else { continue }
                hours.append(HourlyWeather(
                    time: time,
                    tempF: Units.fahrenheit(at("temperature_2m", i), unit: u["temperature_2m"]),
                    humidity: at("relative_humidity_2m", i),
                    rainChance: at("precipitation_probability", i),
                    windMph: Units.mph(at("wind_speed_10m", i), unit: u["wind_speed_10m"])
                ))
            }
        }

        var current: CurrentWeather?
        if let c = r.current, let s = c["time"]?.string, let time = localTime(s, calendar: calendar) {
            let u = r.current_units ?? [:]
            current = CurrentWeather(
                time: time,
                tempF: Units.fahrenheit(c["temperature_2m"]?.double, unit: u["temperature_2m"]),
                humidity: c["relative_humidity_2m"]?.double,
                rainInches: Units.inches(c["precipitation"]?.double, unit: u["precipitation"]),
                windMph: Units.mph(c["wind_speed_10m"]?.double, unit: u["wind_speed_10m"]),
                weatherCode: c["weather_code"]?.double.map { Int($0) }
            )
        }

        return WeatherReport(
            fetchedAt: fetchedAt, timeZoneID: zone.identifier, latitude: r.latitude, longitude: r.longitude,
            current: current, days: days, hours: hours
        )
    }

    /// Parses Open-Meteo's local "2026-07-14T06:00" times in the location's time zone.
    static func localTime(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "T")
        guard parts.count == 2, let day = LocalDay(String(parts[0])) else { return nil }
        let hm = parts[1].split(separator: ":")
        guard hm.count >= 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
        return day.date(atMinute: h * 60 + m, in: calendar)
    }

    /// A short description for a WMO weather code.
    public static func describe(code: Int?) -> String {
        guard let code = code else { return "" }
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 66, 80, 81: return "Rain"
        case 65, 67, 82: return "Heavy rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorms"
        default: return ""
        }
    }

    /// SF Symbol for a WMO weather code.
    public static func symbol(code: Int?) -> String {
        guard let code = code else { return "cloud.sun" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun"
        }
    }
}

/// Converts Open-Meteo values to US units. The app requests metric (Open-Meteo's default), so a
/// missing unit label is read as metric.
public enum Units {
    public static func fahrenheit(_ value: Double?, unit: String?) -> Double? {
        guard let v = value else { return nil }
        if let u = unit, u.uppercased().contains("F") { return v }
        return v * 9 / 5 + 32
    }

    public static func inches(_ value: Double?, unit: String?) -> Double? {
        guard let v = value else { return nil }
        switch unit?.lowercased() {
        case "inch"?, "in"?, "inches"?: return v
        case "cm"?: return v / 2.54
        default: return v / 25.4
        }
    }

    public static func mph(_ value: Double?, unit: String?) -> Double? {
        guard let v = value else { return nil }
        switch unit?.lowercased() {
        case "mph"?, "mp/h"?: return v
        case "m/s"?, "ms"?: return v * 2.23694
        case "kn"?, "knots"?: return v * 1.15078
        default: return v * 0.621371
        }
    }

    /// Gallons that put one inch of water on one square foot.
    public static let gallonsPerInchPerSqFt = 0.623
}
