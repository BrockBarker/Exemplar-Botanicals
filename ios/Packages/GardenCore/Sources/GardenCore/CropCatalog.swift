import Foundation

public enum FeedingNeed: String, Codable, Sendable {
    case heavy, medium, light

    /// Days between routine feeds while flowering or fruiting; nil means no routine feeding
    /// nudges. Most crops do fine on compost-rich soil, so only heavy feeders get them.
    public var feedIntervalDays: Int? {
        switch self {
        case .heavy: return 28
        case .medium, .light: return nil
        }
    }
}

public enum WaterUse: String, Codable, Sendable {
    case low, medium, high

    public var multiplier: Double {
        switch self {
        case .low: return 0.8
        case .medium: return 1.0
        case .high: return 1.15
        }
    }
}

public enum CropGroup: String, Codable, Sendable {
    case vegetable, fruit, herb, flower, other
}

/// What the nudge engine and water model need to know about a kind of plant.
/// Starter values from mainstream US extension guidance; David can tune them.
public struct CropProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let group: CropGroup
    public let feeding: FeedingNeed
    /// Needs a stake, cage or trellis.
    public let needsSupport: Bool
    /// Have support in place this many days after planting.
    public let stakeByDays: Int
    /// Damaged by frost; gets frost warnings.
    public let frostTender: Bool
    /// Fruiting crop: side-dress when it starts to flower.
    public let fruiting: Bool
    /// Benefits from foliar feeding during active growth.
    public let foliarBenefit: Bool
    /// Eaten leaves or roots: urine caution near harvest.
    public let leafyOrRoot: Bool
    /// Base temperature for growing degree days (°F).
    public let gddBaseF: Double
    public let waterUse: WaterUse

    public init(
        id: String, name: String, group: CropGroup, feeding: FeedingNeed,
        needsSupport: Bool = false, stakeByDays: Int = 14, frostTender: Bool,
        fruiting: Bool = false, foliarBenefit: Bool = false, leafyOrRoot: Bool = false,
        gddBaseF: Double = 50, waterUse: WaterUse = .medium
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.feeding = feeding
        self.needsSupport = needsSupport
        self.stakeByDays = stakeByDays
        self.frostTender = frostTender
        self.fruiting = fruiting
        self.foliarBenefit = foliarBenefit
        self.leafyOrRoot = leafyOrRoot
        self.gddBaseF = gddBaseF
        self.waterUse = waterUse
    }

    /// Crop coefficient (share of reference evapotranspiration the plant uses) at a stage.
    public func cropCoefficient(at stage: GrowthStage) -> Double {
        let base: Double
        switch stage {
        case .seed: base = 0.3
        case .seedling: base = 0.5
        case .vegetative: base = 0.8
        case .flowering: base = 1.0
        case .fruiting: base = 1.05
        case .mature: base = 0.9
        case .dormant: base = 0.3
        }
        return base * waterUse.multiplier
    }
}

public enum CropCatalog {
    public static let other = CropProfile(id: "other", name: "Other plant", group: .other, feeding: .medium, frostTender: false)

    /// Crop ids must match the list in the backend's update_plant tool description.
    public static let all: [CropProfile] = [
        CropProfile(id: "tomato", name: "Tomato", group: .vegetable, feeding: .heavy, needsSupport: true, stakeByDays: 10,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "cherry_tomato", name: "Cherry tomato", group: .vegetable, feeding: .heavy, needsSupport: true, stakeByDays: 10,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "pepper", name: "Pepper", group: .vegetable, feeding: .medium, needsSupport: true, stakeByDays: 21,
                    frostTender: true, fruiting: true, foliarBenefit: true),
        CropProfile(id: "eggplant", name: "Eggplant", group: .vegetable, feeding: .heavy, needsSupport: true, stakeByDays: 21,
                    frostTender: true, fruiting: true, foliarBenefit: true),
        CropProfile(id: "cucumber", name: "Cucumber", group: .vegetable, feeding: .medium, needsSupport: true, stakeByDays: 14,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "summer_squash", name: "Summer squash / zucchini", group: .vegetable, feeding: .heavy,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "winter_squash", name: "Winter squash / pumpkin", group: .vegetable, feeding: .heavy,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "melon", name: "Melon", group: .vegetable, feeding: .medium,
                    frostTender: true, fruiting: true, foliarBenefit: true, waterUse: .high),
        CropProfile(id: "corn", name: "Sweet corn", group: .vegetable, feeding: .heavy, frostTender: true, waterUse: .high),
        CropProfile(id: "bush_bean", name: "Bush bean", group: .vegetable, feeding: .light, frostTender: true),
        CropProfile(id: "pole_bean", name: "Pole bean", group: .vegetable, feeding: .light, needsSupport: true, stakeByDays: 7,
                    frostTender: true),
        CropProfile(id: "pea", name: "Pea", group: .vegetable, feeding: .light, needsSupport: true, stakeByDays: 7,
                    frostTender: false, gddBaseF: 40),
        CropProfile(id: "lettuce", name: "Lettuce", group: .vegetable, feeding: .medium, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "spinach", name: "Spinach", group: .vegetable, feeding: .medium, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "kale", name: "Kale", group: .vegetable, feeding: .medium, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "chard", name: "Swiss chard", group: .vegetable, feeding: .medium, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "cabbage", name: "Cabbage", group: .vegetable, feeding: .heavy, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "broccoli", name: "Broccoli", group: .vegetable, feeding: .heavy, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "cauliflower", name: "Cauliflower", group: .vegetable, feeding: .heavy, frostTender: false,
                    foliarBenefit: true, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "carrot", name: "Carrot", group: .vegetable, feeding: .light, frostTender: false,
                    leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "beet", name: "Beet", group: .vegetable, feeding: .light, frostTender: false,
                    leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "radish", name: "Radish", group: .vegetable, feeding: .light, frostTender: false,
                    leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "onion", name: "Onion", group: .vegetable, feeding: .medium, frostTender: false,
                    leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "garlic", name: "Garlic", group: .vegetable, feeding: .medium, frostTender: false,
                    leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "potato", name: "Potato", group: .vegetable, feeding: .medium, frostTender: true,
                    leafyOrRoot: true, gddBaseF: 45),
        CropProfile(id: "sweet_potato", name: "Sweet potato", group: .vegetable, feeding: .light, frostTender: true,
                    leafyOrRoot: true),
        CropProfile(id: "okra", name: "Okra", group: .vegetable, feeding: .medium, frostTender: true, fruiting: true),
        CropProfile(id: "strawberry", name: "Strawberry", group: .fruit, feeding: .medium, frostTender: false,
                    fruiting: true, foliarBenefit: true, gddBaseF: 40),
        CropProfile(id: "blueberry", name: "Blueberry", group: .fruit, feeding: .light, frostTender: false, gddBaseF: 45),
        CropProfile(id: "bramble", name: "Raspberry / blackberry", group: .fruit, feeding: .medium, frostTender: false, gddBaseF: 40),
        CropProfile(id: "basil", name: "Basil", group: .herb, feeding: .light, frostTender: true, foliarBenefit: true),
        CropProfile(id: "perennial_herb", name: "Perennial herb (rosemary, thyme, sage, oregano)", group: .herb,
                    feeding: .light, frostTender: false, gddBaseF: 40, waterUse: .low),
        CropProfile(id: "annual_herb", name: "Annual herb (cilantro, dill, parsley)", group: .herb, feeding: .light,
                    frostTender: false, leafyOrRoot: true, gddBaseF: 40),
        CropProfile(id: "flower_annual", name: "Annual flowers", group: .flower, feeding: .medium, frostTender: true,
                    foliarBenefit: true),
        CropProfile(id: "dahlia", name: "Dahlia", group: .flower, feeding: .medium, needsSupport: true, stakeByDays: 21,
                    frostTender: true, foliarBenefit: true),
        CropProfile(id: "rose", name: "Rose", group: .flower, feeding: .medium, frostTender: false, foliarBenefit: true,
                    gddBaseF: 40),
        CropProfile(id: "fruit_tree", name: "Fruit tree", group: .fruit, feeding: .medium, frostTender: false, gddBaseF: 40),
        CropProfile(id: "citrus", name: "Citrus", group: .fruit, feeding: .heavy, frostTender: true, foliarBenefit: true),
    ]

    private static let byID: [String: CropProfile] = {
        var map: [String: CropProfile] = [:]
        for crop in all { map[crop.id] = crop }
        return map
    }()

    /// The profile for a crop id, or `other` when unknown.
    public static func profile(for id: String?) -> CropProfile {
        guard let id = id, let crop = byID[id] else { return other }
        return crop
    }

    /// Best guess at a crop from a free-text plant name ("Sungold cherry tomato" -> cherry_tomato).
    public static func guess(from name: String) -> CropProfile? {
        let lower = name.lowercased()
        let synonyms: [(String, String)] = [
            ("cherry tomato", "cherry_tomato"), ("sungold", "cherry_tomato"), ("grape tomato", "cherry_tomato"),
            ("tomato", "tomato"), ("pepper", "pepper"), ("jalape", "pepper"), ("eggplant", "eggplant"),
            ("cucumber", "cucumber"), ("zucchini", "summer_squash"), ("summer squash", "summer_squash"),
            ("yellow squash", "summer_squash"), ("pumpkin", "winter_squash"), ("butternut", "winter_squash"),
            ("squash", "winter_squash"), ("melon", "melon"), ("cantaloupe", "melon"), ("corn", "corn"),
            ("pole bean", "pole_bean"), ("bean", "bush_bean"), ("peach", "fruit_tree"), ("pear", "fruit_tree"), ("pea", "pea"), ("lettuce", "lettuce"),
            ("spinach", "spinach"), ("kale", "kale"), ("chard", "chard"), ("cabbage", "cabbage"),
            ("broccoli", "broccoli"), ("cauliflower", "cauliflower"), ("carrot", "carrot"), ("beet", "beet"),
            ("radish", "radish"), ("onion", "onion"), ("garlic", "garlic"), ("sweet potato", "sweet_potato"),
            ("potato", "potato"), ("okra", "okra"), ("strawberr", "strawberry"), ("blueberr", "blueberry"),
            ("raspberr", "bramble"), ("blackberr", "bramble"), ("basil", "basil"), ("rosemary", "perennial_herb"),
            ("thyme", "perennial_herb"), ("sage", "perennial_herb"), ("oregano", "perennial_herb"),
            ("cilantro", "annual_herb"), ("dill", "annual_herb"), ("parsley", "annual_herb"), ("dahlia", "dahlia"),
            ("rose", "rose"), ("lemon", "citrus"), ("lime", "citrus"), ("orange", "citrus"), ("citrus", "citrus"),
            ("apple", "fruit_tree"), ("plum", "fruit_tree"),
            ("fig", "fruit_tree"), ("zinnia", "flower_annual"), ("marigold", "flower_annual"),
            ("sunflower", "flower_annual"), ("cosmos", "flower_annual"),
        ]
        for (needle, id) in synonyms where lower.contains(needle) {
            return byID[id]
        }
        return nil
    }
}
