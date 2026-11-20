import Foundation

/// What the app sends the coach with every request: a compact, name-based picture of the garden.
/// The backend hands it to Claude as JSON (backend/src/garden.ts reads `today`, `timeZone` and
/// `gardener.name`), so keys are camelCase, values use US units, and empty values are left out.
public struct GardenSnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: String
    public var today: String
    public var timeZone: String
    public var gardener: Gardener
    public var location: Location
    public var budget: Budget
    public var preferences: Preferences
    public var inventory: [Item]
    public var beds: [Bed]
    public var plants: [Plant]
    public var coachNotes: [Note]
    /// Newest first.
    public var recentJournal: [Entry]
    public var weather: WeatherSummary?
    public var activeNudges: [ActiveNudge]

    public struct Gardener: Codable, Sendable {
        public var name: String?
    }

    public struct Location: Codable, Sendable {
        public var label: String?
        /// Rounded to about a kilometer; the coach doesn't need more.
        public var latitude: Double?
        public var longitude: Double?
        public var usdaZone: String?
        public var lastSpringFrost: String?
        public var firstFallFrost: String?
    }

    public struct Budget: Codable, Sendable {
        public var monthlyDollars: Double?
        public var notes: String?
    }

    public struct Preferences: Codable, Sendable {
        public var avoidUrine: Bool
    }

    public struct Item: Codable, Sendable {
        public var name: String
        public var category: String
        public var quantity: String?
        public var notes: String?
    }

    public struct Bed: Codable, Sendable {
        public var name: String
        public var kind: String
        public var areaSqFt: Double?
        public var soil: String
        public var sun: String
        public var irrigation: String
        public var mulch: String?
        public var soilPH: Double?
        public var soilTestNotes: String?
        public var notes: String?
        public var water: Water?
    }

    /// The app's estimate of soil water in the bed's root zone (no sensors: weather, watering log, finger tests).
    public struct Water: Codable, Sendable {
        public var status: String
        public var usedInches: Double
        public var holdsInches: Double
        public var lastSoaked: String?
        /// Projected status for the next few days if nobody waters.
        public var outlook: [Outlook]?
    }

    public struct Outlook: Codable, Sendable {
        public var date: String
        public var status: String
    }

    public struct Plant: Codable, Sendable {
        public var name: String
        public var crop: String
        public var bed: String?
        public var plantedOn: String?
        public var daysInGround: Int?
        public var stage: String
        public var count: Int
        public var staked: Bool?
        public var lastFed: String?
        public var lastHarvested: String?
        public var growingDegreeDays: Double?
        public var notes: String?
        public var care: Care?
    }

    /// Starter facts about the crop, so the coach can talk harvest timing, pests and pruning.
    public struct Care: Codable, Sendable {
        public var firstHarvestAroundDay: Int?
        public var readyWhen: String
        public var pickEveryDays: Int?
        public var watchFor: String?
        public var pruning: String?
        public var sowAgainEveryDays: Int?
    }

    public struct Note: Codable, Sendable {
        public var fact: String
        public var category: String
        public var added: String
    }

    public struct Entry: Codable, Sendable {
        public var date: String
        public var kind: String
        public var what: String
        public var amount: String?
        public var bed: String?
        public var plant: String?
        public var moisture: String?
        public var waterInches: Double?
        public var notes: String?
    }

    public struct WeatherSummary: Codable, Sendable {
        public var updated: String
        public var current: Current?
        public var last7Days: Totals?
        public var recentDays: [Day]
        public var forecastDays: [Day]
    }

    public struct Current: Codable, Sendable {
        public var tempF: Double?
        public var humidity: Double?
        public var windMph: Double?
        public var sky: String?
    }

    public struct Totals: Codable, Sendable {
        public var rainInches: Double
        public var evapotranspirationInches: Double
        public var daysWithData: Int
    }

    public struct Day: Codable, Sendable {
        public var date: String
        public var highF: Double?
        public var lowF: Double?
        public var rainInches: Double?
        public var rainChance: Double?
        public var evapotranspirationInches: Double?
        public var gustMph: Double?
        public var sky: String?
    }

    public struct ActiveNudge: Codable, Sendable {
        public var kind: String
        public var title: String
        public var body: String
        public var when: String
    }
}

extension GardenSnapshot {
    /// Builds the snapshot from the app's records.
    public static func make(
        profile: GardenProfileInfo,
        state: GardenState,
        coachNotes: [CoachNoteInfo],
        nudges: [Nudge],
        now: Date,
        calendar: Calendar,
        journalDays: Int = 60,
        maxJournal: Int = 80,
        recentWeatherDays: Int = 14
    ) -> GardenSnapshot {
        let today = LocalDay(now, calendar: calendar)

        let inventory = state.inventory.map {
            Item(name: $0.name, category: $0.category.rawValue, quantity: nonEmpty($0.quantity), notes: nonEmpty($0.notes))
        }

        let beds = state.beds.map { bed -> Bed in
            let plants = state.plants(in: bed)
            let ws = WaterModel.state(
                bed: bed, plants: plants, journal: state.journal, weather: state.weather, today: today, calendar: calendar
            )
            let water: Water? = ws.status == .unknown ? nil : Water(
                status: ws.status.rawValue,
                usedInches: round2(ws.deficitInches),
                holdsInches: round2(ws.capacityInches),
                lastSoaked: ws.lastRefillDay?.string,
                outlook: ws.projected.isEmpty ? nil : ws.projected.map { Outlook(date: $0.day.string, status: $0.status.rawValue) }
            )
            return Bed(
                name: bed.name, kind: bed.kind.rawValue, areaSqFt: bed.areaSqFt.map(round1), soil: bed.soilType.rawValue,
                sun: bed.sun.rawValue, irrigation: bed.irrigation.rawValue, mulch: bed.isMulched ? bed.mulch : nil,
                soilPH: bed.soilPH.map(round1), soilTestNotes: nonEmpty(bed.soilTestNotes), notes: nonEmpty(bed.notes), water: water
            )
        }

        let yesterday = today.adding(days: -1, calendar: calendar)
        let plants = state.plants.map { plant -> Plant in
            let bedName = state.bedName(for: plant)
            let lastFed = state.journal
                .filter { $0.kind.countsAsFeeding && $0.applies(to: plant, bedName: bedName) }
                .map { $0.day }
                .max()
            let lastHarvested = state.journal
                .filter { $0.kind == .harvest && $0.applies(to: plant, bedName: bedName) }
                .map { $0.day }
                .max()
            let crop = plant.crop
            let care: Care? = crop.id == CropCatalog.other.id ? nil : Care(
                firstHarvestAroundDay: crop.care.firstHarvestDays,
                readyWhen: crop.care.readyWhen,
                pickEveryDays: crop.care.pickEveryDays,
                watchFor: crop.care.watchFor,
                pruning: crop.care.prune,
                sowAgainEveryDays: crop.care.sowAgainDays
            )
            var gdd: Double?
            if let planted = plant.plantedOn, let weather = state.weather, planted <= yesterday {
                let total = Agronomy.gddTotal(weather.days, from: planted, through: yesterday, baseF: plant.crop.gddBaseF, calendar: calendar)
                // Only report it when the weather history covers most of the season.
                let span = planted.days(to: yesterday, calendar: calendar) + 1
                if total.missingDays * 4 <= span { gdd = total.total.rounded() }
            }
            return Plant(
                name: plant.name,
                crop: plant.cropID ?? CropCatalog.other.id,
                bed: bedName,
                plantedOn: plant.plantedOn?.string,
                daysInGround: plant.plantedOn.map { $0.days(to: today, calendar: calendar) },
                stage: plant.stage.rawValue,
                count: plant.count,
                staked: plant.crop.needsSupport ? plant.staked : nil,
                lastFed: lastFed?.string,
                lastHarvested: lastHarvested?.string,
                growingDegreeDays: gdd,
                notes: nonEmpty(plant.notes),
                care: care
            )
        }

        let bedNames = Dictionary(state.beds.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let plantNames = Dictionary(state.plants.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let cutoff = today.adding(days: -journalDays, calendar: calendar)
        let journal = state.journal
            .filter { $0.day >= cutoff && $0.day <= today }
            .sorted { $0.day > $1.day }
            .prefix(maxJournal)
            .map { e -> Entry in
                let bed = e.bedID.flatMap { bedNames[$0] } ?? nonEmpty(e.bedName)
                let plant = e.plantID.flatMap { plantNames[$0] } ?? nonEmpty(e.plantName)
                return Entry(
                    date: e.day.string, kind: e.kind.rawValue, what: e.what, amount: nonEmpty(e.amount), bed: bed, plant: plant,
                    moisture: e.moisture?.rawValue, waterInches: e.waterInches.map(round2), notes: nonEmpty(e.notes)
                )
            }

        let notes = coachNotes.map { Note(fact: $0.fact, category: $0.category.rawValue, added: $0.added.string) }

        let active = nudges
            .filter { $0.fireDate >= now.addingTimeInterval(-12 * 3600) && $0.fireDate <= now.addingTimeInterval(3 * 86_400) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(8)
            .map { ActiveNudge(kind: $0.kind.rawValue, title: $0.title, body: $0.body, when: localTimestamp($0.fireDate, calendar: calendar)) }

        return GardenSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: localTimestamp(now, calendar: calendar),
            today: today.string,
            timeZone: calendar.timeZone.identifier,
            gardener: Gardener(name: nonEmpty(profile.gardenerName)),
            location: Location(
                label: nonEmpty(profile.locationLabel),
                latitude: profile.latitude.map(round2),
                longitude: profile.longitude.map(round2),
                usdaZone: nonEmpty(profile.usdaZone),
                lastSpringFrost: profile.lastSpringFrost?.string,
                firstFallFrost: profile.firstFallFrost?.string
            ),
            budget: Budget(monthlyDollars: profile.monthlyBudget, notes: nonEmpty(profile.budgetNotes)),
            preferences: Preferences(avoidUrine: profile.avoidUrine),
            inventory: inventory,
            beds: beds,
            plants: plants,
            coachNotes: notes,
            recentJournal: Array(journal),
            weather: state.weather.map { weatherSummary($0, today: today, now: now, calendar: calendar, recentDays: recentWeatherDays) },
            activeNudges: Array(active)
        )
    }

    static func weatherSummary(_ w: WeatherReport, today: LocalDay, now: Date, calendar: Calendar, recentDays: Int) -> WeatherSummary {
        func day(_ d: DailyWeather) -> Day {
            Day(
                date: d.day.string,
                highF: d.highF.map { $0.rounded() },
                lowF: d.lowF.map { $0.rounded() },
                rainInches: d.rainInches.map(round2),
                rainChance: d.rainChance.map { $0.rounded() },
                evapotranspirationInches: d.et0Inches.map(round2),
                gustMph: d.windForStakes.map { $0.rounded() },
                sky: nonEmpty(OpenMeteo.describe(code: d.weatherCode))
            )
        }
        let recent = w.days(from: today.adding(days: -recentDays, calendar: calendar), through: today.adding(days: -1, calendar: calendar))
        let last7 = w.days(from: today.adding(days: -7, calendar: calendar), through: today.adding(days: -1, calendar: calendar))
        let totals: Totals? = last7.isEmpty ? nil : Totals(
            rainInches: round2(last7.compactMap { $0.rainInches }.reduce(0, +)),
            evapotranspirationInches: round2(last7.compactMap { $0.et0Inches }.reduce(0, +)),
            daysWithData: last7.count
        )
        let current = w.current.map {
            Current(
                tempF: $0.tempF.map { $0.rounded() }, humidity: $0.humidity.map { $0.rounded() },
                windMph: $0.windMph.map { $0.rounded() }, sky: nonEmpty(OpenMeteo.describe(code: $0.weatherCode))
            )
        }
        return WeatherSummary(
            updated: localTimestamp(w.fetchedAt, calendar: calendar),
            current: current,
            last7Days: totals,
            recentDays: recent.map(day),
            forecastDays: w.days.filter { $0.day >= today }.prefix(8).map(day)
        )
    }

    /// The JSON encoder used for requests (stable key order makes requests easy to compare).
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// "2026-07-14 06:30" in the garden's time zone.
func localTimestamp(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return String(format: "%04ld-%02ld-%02ld %02ld:%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
}

func nonEmpty(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
