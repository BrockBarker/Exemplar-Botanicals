import Foundation

/// Growing degree days and a simple bucket model of soil water. No sensors: the model runs on
/// weather (rain and ET₀), logged watering, and the gardener's finger-test check-ins.
public enum Agronomy {
    /// Growing degree days for one day, modified method: temperatures are capped at 86°F and
    /// lows are floored at the base temperature.
    public static func gdd(highF: Double, lowF: Double, baseF: Double = 50, capF: Double = 86) -> Double {
        let hi = min(max(highF, baseF), capF)
        let lo = min(max(lowF, baseF), capF)
        return max(0, (hi + lo) / 2 - baseF)
    }

    public struct GDDTotal: Equatable, Sendable {
        public var total: Double
        /// Days in the range with no temperature data (total is a lower bound when > 0).
        public var missingDays: Int
    }

    /// Accumulated GDD over an inclusive range of days.
    public static func gddTotal(_ days: [DailyWeather], from start: LocalDay, through end: LocalDay, baseF: Double, calendar: Calendar) -> GDDTotal {
        guard start <= end else { return GDDTotal(total: 0, missingDays: 0) }
        var byDay: [LocalDay: DailyWeather] = [:]
        for d in days { byDay[d.day] = d }
        var total = 0.0
        var missing = 0
        var day = start
        var guardCount = 0
        while day <= end && guardCount < 800 {
            if let d = byDay[day], let hi = d.highF, let lo = d.lowF {
                total += gdd(highF: hi, lowF: lo, baseF: baseF)
            } else {
                missing += 1
            }
            day = day.adding(days: 1, calendar: calendar)
            guardCount += 1
        }
        return GDDTotal(total: total, missingDays: missing)
    }
}

public enum WaterStatus: String, Codable, Sendable {
    case ok
    case check
    case dry
    case unknown

    public var displayName: String {
        switch self {
        case .ok: return "OK"
        case .check: return "Check soon"
        case .dry: return "Likely dry"
        case .unknown: return "Not enough data"
        }
    }
}

public struct WaterState: Codable, Hashable, Sendable {
    /// Inches of plant-available water used up in the root zone.
    public var deficitInches: Double
    /// Inches of plant-available water the root zone holds when fully watered.
    public var capacityInches: Double
    public var status: WaterStatus
    /// Last day it was watered, rained meaningfully, or checked moist.
    public var lastRefillDay: LocalDay?
    /// Projected deficit at the end of each upcoming forecast day, assuming no watering.
    public var projected: [ProjectedWater]

    public struct ProjectedWater: Codable, Hashable, Sendable {
        public var day: LocalDay
        public var deficitInches: Double
        public var status: WaterStatus
    }

    public var fraction: Double { capacityInches > 0 ? deficitInches / capacityInches : 0 }
}

public enum WaterModel {
    /// Readily available water in the top foot of soil, inches.
    public static func capacity(soil: SoilType, kind: BedKind) -> Double {
        let base: Double
        switch soil {
        case .sand: base = 0.5
        case .sandyLoam: base = 0.8
        case .loam: base = 1.0
        case .siltLoam: base = 1.1
        case .clayLoam: base = 1.0
        case .clay: base = 0.9
        case .pottingMix: base = 0.7
        case .unknown: base = 0.8
        }
        switch kind {
        case .container: return min(base, 0.7) * 0.6
        case .raised: return base * 0.9
        case .inGround, .row: return base
        }
    }

    /// How much faster than reference ET this bed loses water.
    public static func etMultiplier(bed: BedInfo) -> Double {
        var m = 1.0
        switch bed.kind {
        case .container: m *= 1.3
        case .raised: m *= 1.05
        case .inGround, .row: break
        }
        switch bed.sun {
        case .fullSun: break
        case .partSun: m *= 0.85
        case .partShade: m *= 0.7
        case .shade: m *= 0.55
        }
        if bed.isMulched { m *= 0.8 }
        return m
    }

    /// Crop coefficient for a bed: its thirstiest active plant, or bare soil when empty.
    public static func cropCoefficient(for plants: [PlantInfo]) -> Double {
        let values = plants.map { $0.crop.cropCoefficient(at: $0.stage) }
        return values.max() ?? 0.4
    }

    /// Rain that actually reaches the root zone (light showers mostly evaporate).
    public static func effectiveRain(_ inches: Double) -> Double {
        max(0, inches - 0.05) * 0.9
    }

    public static func status(fraction: Double) -> WaterStatus {
        if fraction >= 0.7 { return .dry }
        if fraction >= 0.45 { return .check }
        return .ok
    }

    /// Runs the bucket model for one bed up to the end of yesterday, applies today's logged
    /// watering, and projects the next few forecast days.
    public static func state(
        bed: BedInfo,
        plants: [PlantInfo],
        journal: [JournalInfo],
        weather: WeatherReport?,
        today: LocalDay,
        calendar: Calendar,
        lookbackDays: Int = 21,
        projectDays: Int = 4
    ) -> WaterState {
        let cap = capacity(soil: bed.soilType, kind: bed.kind)
        let kc = cropCoefficient(for: plants)
        let mult = etMultiplier(bed: bed)
        let bedEntries = journal.filter { entry in
            if entry.applies(to: bed) { return true }
            // Entries logged against one of this bed's plants count for the bed too.
            return plants.contains { plant in
                if let pid = entry.plantID { return pid == plant.id }
                return !entry.plantName.isEmpty && entry.plantName.caseInsensitiveCompare(plant.name) == .orderedSame
            }
        }

        var waterByDay: [LocalDay: Double] = [:]
        var checkByDay: [LocalDay: MoistureReading] = [:]
        for e in bedEntries {
            if e.kind == .watering {
                waterByDay[e.day, default: 0] += e.waterInches
                    ?? WaterAmount.inches(amount: e.amount, what: e.what, areaSqFt: bed.areaSqFt)
            }
            if let m = e.moisture, e.kind == .moistureCheck || e.kind == .watering || e.kind == .observation {
                checkByDay[e.day] = m
            }
        }

        guard let weather = weather else {
            return WaterState(deficitInches: 0, capacityInches: cap, status: .unknown, lastRefillDay: nil, projected: [])
        }

        // Start from the most recent finger test in the window, else assume partly used.
        let windowStart = today.adding(days: -lookbackDays, calendar: calendar)
        let recentCheck = checkByDay.keys.filter { $0 >= windowStart && $0 < today }.max()
        var deficit = cap * 0.3
        var day = windowStart
        var lastRefill: LocalDay?
        if let checkDay = recentCheck, let reading = checkByDay[checkDay] {
            deficit = cap * reading.depletionFraction
            day = checkDay.adding(days: 1, calendar: calendar)
            if reading == .moist || reading == .wet { lastRefill = checkDay }
        }

        var byDay: [LocalDay: DailyWeather] = [:]
        for d in weather.days { byDay[d.day] = d }
        var knownDays = 0

        var guardCount = 0
        while day < today && guardCount < 400 {
            if let w = byDay[day] {
                if let et = w.et0Inches { deficit += et * kc * mult; knownDays += 1 }
                if let rain = w.rainInches {
                    let eff = effectiveRain(rain)
                    deficit -= eff
                    if eff >= 0.25 { lastRefill = day }
                }
            }
            if let water = waterByDay[day], water > 0 {
                deficit -= water
                if water >= 0.25 { lastRefill = day }
            }
            if let reading = checkByDay[day] {
                deficit = cap * reading.depletionFraction
                if reading == .moist || reading == .wet { lastRefill = day }
            }
            deficit = min(max(deficit, 0), cap)
            day = day.adding(days: 1, calendar: calendar)
            guardCount += 1
        }

        // Watering or a check-in logged today counts right away.
        if let water = waterByDay[today], water > 0 {
            deficit = max(0, deficit - water)
            if water >= 0.25 { lastRefill = today }
        }
        if let reading = checkByDay[today] {
            deficit = cap * reading.depletionFraction
            if reading == .moist || reading == .wet { lastRefill = today }
        }

        let hadData = knownDays > 0 || recentCheck != nil || checkByDay[today] != nil
        var projected: [WaterState.ProjectedWater] = []
        var future = deficit
        for offset in 0..<projectDays {
            let d = today.adding(days: offset, calendar: calendar)
            guard let w = byDay[d], let et = w.et0Inches else { break }
            future += et * kc * mult
            future -= effectiveRain(w.rainInches ?? 0)
            future = min(max(future, 0), cap)
            projected.append(.init(day: d, deficitInches: future, status: status(fraction: cap > 0 ? future / cap : 0)))
        }

        return WaterState(
            deficitInches: deficit,
            capacityInches: cap,
            status: hadData ? status(fraction: cap > 0 ? deficit / cap : 0) : .unknown,
            lastRefillDay: lastRefill,
            projected: projected
        )
    }
}

/// Reads a watering amount from free text ("2 gallons", "about an inch", "deep soak").
public enum WaterAmount {
    public static let deep = 1.0
    public static let normal = 0.5
    public static let light = 0.25

    /// Bed area assumed when converting gallons and the bed has no size (a 4 x 8 ft raised bed).
    public static let defaultAreaSqFt = 32.0

    public static func inches(amount: String, what: String, areaSqFt: Double?) -> Double {
        let text = (amount + " " + what).lowercased()
        let tokens = tokenize(text)
        for (i, token) in tokens.enumerated() {
            guard let value = number(token) else { continue }
            let unit = i + 1 < tokens.count ? tokens[i + 1] : ""
            if unit.hasPrefix("gal") {
                let area = (areaSqFt ?? 0) > 0 ? areaSqFt! : defaultAreaSqFt
                return min(3, value / (Units.gallonsPerInchPerSqFt * area))
            }
            if unit.hasPrefix("inch") || unit == "in" || unit == "\"" {
                return min(3, value)
            }
        }
        if text.contains("half an inch") || text.contains("half inch") { return 0.5 }
        if text.contains("an inch") || text.contains("one inch") { return 1.0 }
        if text.contains("deep") || text.contains("soak") || text.contains("thorough") { return deep }
        if text.contains("light") || text.contains("quick") || text.contains("sprinkl") || text.contains("splash") { return light }
        return normal
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        for ch in text {
            if ch.isNumber || ch == "." || ch == "/" {
                if let last = current.last, !(last.isNumber || last == "." || last == "/") { flush() }
                current.append(ch)
            } else if ch.isLetter {
                if let last = current.last, last.isNumber || last == "." || last == "/" { flush() }
                current.append(ch)
            } else if ch == "\"" {
                flush()
                tokens.append("\"")
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func number(_ token: String) -> Double? {
        if let v = Double(token) { return v }
        let parts = token.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return nil
    }
}
