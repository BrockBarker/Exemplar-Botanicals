import Foundation

// Shared vocabulary. Raw values must match backend/src/vocab.ts, because the coach
// sends them back in record-keeping actions and diagnoses.

public enum JournalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case watering
    case feeding
    case foliarSpray = "foliar_spray"
    case amendment
    case mulching
    case staking
    case planting
    case transplanting
    case pruning
    case harvest
    case moistureCheck = "moisture_check"
    case pestOrDisease = "pest_or_disease"
    case observation
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .watering: return "Watering"
        case .feeding: return "Feeding"
        case .foliarSpray: return "Foliar spray"
        case .amendment: return "Soil amendment"
        case .mulching: return "Mulching"
        case .staking: return "Staking"
        case .planting: return "Planting"
        case .transplanting: return "Transplanting"
        case .pruning: return "Pruning"
        case .harvest: return "Harvest"
        case .moistureCheck: return "Moisture check"
        case .pestOrDisease: return "Pest or disease"
        case .observation: return "Observation"
        case .other: return "Other"
        }
    }

    /// SF Symbol name used in the journal list.
    public var symbol: String {
        switch self {
        case .watering: return "drop.fill"
        case .feeding: return "leaf.arrow.triangle.circlepath"
        case .foliarSpray: return "sprinkler.and.droplets.fill"
        case .amendment: return "square.stack.3d.down.right.fill"
        case .mulching: return "square.3.layers.3d.down.left"
        case .staking: return "line.3.horizontal.decrease"
        case .planting, .transplanting: return "leaf.fill"
        case .pruning: return "scissors"
        case .harvest: return "basket.fill"
        case .moistureCheck: return "hand.point.down.fill"
        case .pestOrDisease: return "ant.fill"
        case .observation: return "eye.fill"
        case .other: return "square.and.pencil"
        }
    }

    /// Entries that count as feeding the soil or plant when the nudge engine checks for over-feeding.
    public var countsAsFeeding: Bool {
        self == .feeding || self == .amendment
    }
}

public enum InventoryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case fertilizer
    case amendment
    case foliar
    case rockDust = "rock_dust"
    case compost
    case mulch
    case biological
    case pestControl = "pest_control"
    case tool
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fertilizer: return "Fertilizer"
        case .amendment: return "Soil amendment"
        case .foliar: return "Foliar spray"
        case .rockDust: return "Rock dust"
        case .compost: return "Compost"
        case .mulch: return "Mulch"
        case .biological: return "Biological"
        case .pestControl: return "Organic pest control"
        case .tool: return "Tool"
        case .other: return "Other"
        }
    }
}

public enum GrowthStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case seed
    case seedling
    case vegetative
    case flowering
    case fruiting
    case mature
    case dormant

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .seed: return "Seed"
        case .seedling: return "Seedling"
        case .vegetative: return "Growing"
        case .flowering: return "Flowering"
        case .fruiting: return "Fruiting"
        case .mature: return "Mature / harvesting"
        case .dormant: return "Dormant"
        }
    }

    /// Stages where the plant is actively growing and feeding, staking and foliar sprays matter.
    public var isActive: Bool {
        switch self {
        case .seedling, .vegetative, .flowering, .fruiting: return true
        case .seed, .mature, .dormant: return false
        }
    }
}

public enum BedKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case inGround = "in_ground"
    case raised
    case container
    case row

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inGround: return "In-ground bed"
        case .raised: return "Raised bed"
        case .container: return "Container"
        case .row: return "Row"
        }
    }
}

public enum SoilType: String, Codable, CaseIterable, Identifiable, Sendable {
    case sand
    case sandyLoam = "sandy_loam"
    case loam
    case siltLoam = "silt_loam"
    case clayLoam = "clay_loam"
    case clay
    case pottingMix = "potting_mix"
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sand: return "Sand"
        case .sandyLoam: return "Sandy loam"
        case .loam: return "Loam"
        case .siltLoam: return "Silt loam"
        case .clayLoam: return "Clay loam"
        case .clay: return "Clay"
        case .pottingMix: return "Potting mix"
        case .unknown: return "Not sure"
        }
    }
}

public enum SunExposure: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullSun = "full_sun"
    case partSun = "part_sun"
    case partShade = "part_shade"
    case shade

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullSun: return "Full sun (6+ hours)"
        case .partSun: return "Part sun (4–6 hours)"
        case .partShade: return "Part shade (2–4 hours)"
        case .shade: return "Shade (under 2 hours)"
        }
    }
}

public enum IrrigationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hand
    case hose
    case soaker
    case drip
    case sprinkler
    case rainOnly = "rain_only"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hand: return "Watering can"
        case .hose: return "Hose"
        case .soaker: return "Soaker hose"
        case .drip: return "Drip"
        case .sprinkler: return "Sprinkler"
        case .rainOnly: return "Rain only"
        }
    }
}

/// What the soil felt like about 2 inches down (the finger test).
public enum MoistureReading: String, Codable, CaseIterable, Identifiable, Sendable {
    case dry
    case slightlyMoist = "slightly_moist"
    case moist
    case wet

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dry: return "Dry"
        case .slightlyMoist: return "Slightly moist"
        case .moist: return "Moist"
        case .wet: return "Wet"
        }
    }

    /// Share of the bed's available water that is used up when the soil feels like this.
    public var depletionFraction: Double {
        switch self {
        case .dry: return 0.85
        case .slightlyMoist: return 0.55
        case .moist: return 0.25
        case .wet: return 0.0
        }
    }
}

public enum FactCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case soil, water, sun, pests, wildlife, preference, equipment, history, other
    public var id: String { rawValue }
}

/// The order every recommendation follows: what you own, then free, then low cost, then branded.
public enum Tier: String, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case owned
    case free
    case lowCost = "low_cost"
    case branded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .owned: return "You have this"
        case .free: return "Free"
        case .lowCost: return "Low cost"
        case .branded: return "Buy"
        }
    }

    public var rank: Int {
        switch self {
        case .owned: return 0
        case .free: return 1
        case .lowCost: return 2
        case .branded: return 3
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }
}
