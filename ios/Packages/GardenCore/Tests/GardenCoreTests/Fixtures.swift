import Foundation
@testable import GardenCore

/// Shared test data: a garden in Chicago on Tuesday, July 14, 2026.
enum Fixtures {
    static let zone = "America/Chicago"
    static let calendar = Calendar.garden(timeZoneID: zone)
    static let today = LocalDay(year: 2026, month: 7, day: 14)

    static func day(_ offset: Int) -> LocalDay {
        today.adding(days: offset, calendar: calendar)
    }

    /// A time on a day relative to today, in the garden's time zone.
    static func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        day(offset).date(atMinute: hour * 60 + minute, in: calendar)
    }

    /// 6:00 AM today: before the usual 7:30 AM delivery time.
    static var morning: Date { at(0, 6) }

    /// Daily weather from `past` days ago through `future` days ahead. `configure` gets the
    /// offset from today and can change any day.
    static func weather(
        past: Int = 21, future: Int = 7,
        high: Double = 80, low: Double = 62, rain: Double = 0, rainChance: Double = 10, et0: Double = 0.15, gust: Double = 10,
        hours: [HourlyWeather] = [],
        configure: (Int, inout DailyWeather) -> Void = { _, _ in }
    ) -> WeatherReport {
        var days: [DailyWeather] = []
        for offset in -past...future {
            var d = DailyWeather(
                day: day(offset), highF: high, lowF: low, rainInches: rain, rainChance: rainChance,
                et0Inches: et0, windMaxMph: gust * 0.6, gustMaxMph: gust, weatherCode: 1
            )
            configure(offset, &d)
            days.append(d)
        }
        return WeatherReport(
            fetchedAt: morning, timeZoneID: zone, latitude: 41.88, longitude: -87.63,
            current: CurrentWeather(time: morning, tempF: 70, humidity: 60, rainInches: 0, windMph: 5, weatherCode: 1),
            days: days, hours: hours
        )
    }

    /// Hourly weather starting at midnight today.
    static func hours(count: Int = 72, temp: Double = 70, wind: Double = 4, rainChance: Double = 0) -> [HourlyWeather] {
        (0..<count).map { h in
            HourlyWeather(time: at(0, 0).addingTimeInterval(Double(h) * 3600), tempF: temp, humidity: 60, rainChance: rainChance, windMph: wind)
        }
    }

    static func bed(_ name: String = "Back bed", kind: BedKind = .raised, soil: SoilType = .loam, mulch: String = "") -> BedInfo {
        BedInfo(name: name, kind: kind, areaSqFt: 32, soilType: soil, sun: .fullSun, irrigation: .hose, mulch: mulch)
    }

    static func plant(
        _ name: String, crop: String, bed: BedInfo? = nil, plantedDaysAgo: Int? = nil,
        stage: GrowthStage = .vegetative, staked: Bool = false
    ) -> PlantInfo {
        PlantInfo(
            name: name, cropID: crop, bedID: bed?.id, plantedOn: plantedDaysAgo.map { day(-$0) }, stage: stage, staked: staked
        )
    }

    static func state(
        beds: [BedInfo] = [], plants: [PlantInfo] = [], journal: [JournalInfo] = [],
        inventory: [InventoryInfo] = [], weather: WeatherReport? = nil
    ) -> GardenState {
        GardenState(beds: beds, plants: plants, journal: journal, inventory: inventory, weather: weather)
    }

    static var engine: NudgeEngine { NudgeEngine(settings: .standard, calendar: calendar) }

    static func nudge(
        _ key: String, kind: NudgeKind = .staking, priority: Int = 50, at date: Date, cooldownDays: Int = 1, expires: Date? = nil
    ) -> Nudge {
        Nudge(kind: kind, dedupeKey: key, cooldownDays: cooldownDays, priority: priority, fireDate: date, expires: expires, title: key, body: key)
    }
}
