import Foundation

/// A calendar day in the garden's own time zone, independent of the phone's.
/// Encodes as "YYYY-MM-DD", the format Open-Meteo and the backend use.
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public var string: String {
        String(format: "%04ld-%02ld-%02ld", year, month, day)
    }

    public var description: String { string }

    /// Midnight at the start of this day in the calendar's time zone.
    public func startDate(in calendar: Calendar) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 0
        c.minute = 0
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// A time of day on this day, in minutes after midnight.
    public func date(atMinute minute: Int, in calendar: Calendar) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = minute / 60
        c.minute = minute % 60
        return calendar.date(from: c) ?? startDate(in: calendar)
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        let noon = date(atMinute: 12 * 60, in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: noon) ?? noon
        return LocalDay(moved, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: LocalDay, calendar: Calendar) -> Int {
        let a = date(atMinute: 12 * 60, in: calendar)
        let b = other.date(atMinute: 12 * 60, in: calendar)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "Today", "Tomorrow", or a weekday name ("Thursday") for days within a week.
    public func spokenName(relativeTo today: LocalDay, calendar: Calendar) -> String {
        let offset = today.days(to: self, calendar: calendar)
        switch offset {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default:
            let weekday = calendar.component(.weekday, from: date(atMinute: 12 * 60, in: calendar))
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let name = names[(weekday - 1 + 7) % 7]
            return offset > 1 && offset < 7 ? name : "\(name) \(month)/\(day)"
        }
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let day = LocalDay(s) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(s)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public extension Calendar {
    /// A Gregorian calendar in the given time zone (falls back to the phone's zone).
    static func garden(timeZoneID: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let id = timeZoneID, let zone = TimeZone(identifier: id) {
            calendar.timeZone = zone
        } else {
            calendar.timeZone = TimeZone.current
        }
        return calendar
    }

    /// Minutes after midnight for a date, in this calendar's time zone.
    func minuteOfDay(_ date: Date) -> Int {
        let c = dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
