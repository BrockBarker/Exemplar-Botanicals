import Foundation

public enum NudgeKind: String, Codable, CaseIterable, Sendable {
    case frost
    case heatStress = "heat_stress"
    case drySpell = "dry_spell"
    case waterNow = "water_now"
    case moistureCheck = "moisture_check"
    case wind
    case staking
    case foliar
    case firstFeed = "first_feed"
    case feed
    case harvest
    case pestCheck = "pest_check"
    case pruning
    case succession
    case seasonEnd = "season_end"

    public var displayName: String {
        switch self {
        case .frost: return "Frost warning"
        case .heatStress: return "Heat stress"
        case .drySpell: return "Dry spell"
        case .waterNow: return "Water now"
        case .moistureCheck: return "Moisture check"
        case .wind: return "Wind"
        case .staking: return "Staking"
        case .foliar: return "Foliar spray"
        case .firstFeed: return "First feeding"
        case .feed: return "Feeding"
        case .harvest: return "Harvest"
        case .pestCheck: return "Pest check"
        case .pruning: return "Pruning"
        case .succession: return "Sow again"
        case .seasonEnd: return "End of season"
        }
    }

    public var symbol: String {
        switch self {
        case .frost: return "snowflake"
        case .heatStress: return "thermometer.sun.fill"
        case .drySpell: return "sun.max.fill"
        case .waterNow: return "drop.fill"
        case .moistureCheck: return "hand.point.down.fill"
        case .wind: return "wind"
        case .staking: return "arrow.up.to.line"
        case .foliar: return "sprinkler.and.droplets.fill"
        case .firstFeed, .feed: return "leaf.fill"
        case .harvest: return "basket.fill"
        case .pestCheck: return "ant.fill"
        case .pruning: return "scissors"
        case .succession: return "leaf.arrow.circlepath"
        case .seasonEnd: return "calendar.badge.clock"
        }
    }
}

/// How nudges are paced so they help without nagging. Defaults answer the spec's open
/// question; the gardener can change them in Settings.
public struct NudgeSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = true
    public var maxPerDay: Int = 2
    /// Quiet hours, in minutes after midnight (default 9 PM to 7 AM).
    public var quietStartMinute: Int = 21 * 60
    public var quietEndMinute: Int = 7 * 60
    /// Preferred time for routine nudges (default 7:30 AM).
    public var deliveryMinute: Int = 7 * 60 + 30
    public var foliarIntervalDays: Int = 21
    public var heatThresholdF: Double = 90
    public var frostThresholdF: Double = 34
    public var windThresholdMph: Double = 25
    public var minimumSpacingMinutes: Int = 120

    public init() {}

    public static let standard = NudgeSettings()

    public func isQuiet(minute: Int) -> Bool {
        if quietStartMinute == quietEndMinute { return false }
        if quietStartMinute > quietEndMinute {
            return minute >= quietStartMinute || minute < quietEndMinute
        }
        return minute >= quietStartMinute && minute < quietEndMinute
    }
}

/// What tapping "Done" on a nudge writes to the journal.
public struct SuggestedLog: Codable, Hashable, Sendable {
    public var kind: JournalKind
    public var what: String
    public var bedIDs: [UUID]
    public var plantIDs: [UUID]
    public var waterInches: Double?

    public init(kind: JournalKind, what: String, bedIDs: [UUID] = [], plantIDs: [UUID] = [], waterInches: Double? = nil) {
        self.kind = kind
        self.what = what
        self.bedIDs = bedIDs
        self.plantIDs = plantIDs
        self.waterInches = waterInches
    }
}

public struct Nudge: Codable, Hashable, Identifiable, Sendable {
    public var kind: NudgeKind
    /// Same key = same reminder; used for cooldowns and snoozes.
    public var dedupeKey: String
    /// Days before the same reminder may fire again (0 = only once per key).
    public var cooldownDays: Int
    public var priority: Int
    public var fireDate: Date
    /// After this the nudge is no longer useful (e.g. the frost already came).
    public var expires: Date?
    public var title: String
    public var body: String
    /// Longer explanation shown in the app, with options in use-what-you-have order.
    public var detail: String
    public var bedIDs: [UUID]
    public var plantIDs: [UUID]
    public var log: SuggestedLog?

    public var id: String { "\(dedupeKey)|\(Int(fireDate.timeIntervalSince1970))" }

    public init(
        kind: NudgeKind, dedupeKey: String, cooldownDays: Int, priority: Int, fireDate: Date, expires: Date? = nil,
        title: String, body: String, detail: String = "", bedIDs: [UUID] = [], plantIDs: [UUID] = [], log: SuggestedLog? = nil
    ) {
        self.kind = kind
        self.dedupeKey = dedupeKey
        self.cooldownDays = cooldownDays
        self.priority = priority
        self.fireDate = fireDate
        self.expires = expires
        self.title = title
        self.body = body
        self.detail = detail
        self.bedIDs = bedIDs
        self.plantIDs = plantIDs
        self.log = log
    }
}

/// A nudge that was delivered, acted on, or snoozed.
public struct NudgeHistory: Codable, Hashable, Sendable {
    public var dedupeKey: String
    public var date: Date
    public var snoozedUntil: Date?

    public init(dedupeKey: String, date: Date, snoozedUntil: Date? = nil) {
        self.dedupeKey = dedupeKey
        self.date = date
        self.snoozedUntil = snoozedUntil
    }
}

public struct GardenState: Sendable {
    public var beds: [BedInfo]
    public var plants: [PlantInfo]
    public var journal: [JournalInfo]
    public var inventory: [InventoryInfo]
    public var weather: WeatherReport?
    /// From the gardener's profile, when they've set them.
    public var lastSpringFrost: LocalDay?
    public var firstFallFrost: LocalDay?

    public init(
        beds: [BedInfo], plants: [PlantInfo], journal: [JournalInfo], inventory: [InventoryInfo], weather: WeatherReport?,
        lastSpringFrost: LocalDay? = nil, firstFallFrost: LocalDay? = nil
    ) {
        self.beds = beds
        self.plants = plants
        self.journal = journal
        self.inventory = inventory
        self.weather = weather
        self.lastSpringFrost = lastSpringFrost
        self.firstFallFrost = firstFallFrost
    }

    public func plants(in bed: BedInfo) -> [PlantInfo] {
        plants.filter { $0.bedID == bed.id }
    }

    public func bedName(for plant: PlantInfo) -> String? {
        guard let id = plant.bedID else { return nil }
        return beds.first { $0.id == id }?.name
    }
}
