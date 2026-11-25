import Foundation

/// What a nudge is asking the gardener to supply.
public enum GardenNeed: String, Codable, Sendable {
    case feed
    case foliar
    case mulch
    case frostCover
    case pests
}

/// A starter list of organic options the app can suggest offline (nudges, demo mode).
/// The live coach uses David's persona files instead; these mirror the same principles.
public struct OrganicOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tier: Tier
    public let needs: Set<GardenNeed>
    public let howTo: String
    public let caution: String
    public let price: String
    /// Lowercased fragments that identify this product in an inventory item's name.
    public let keywords: [String]
    public let isUrine: Bool

    public init(
        id: String, name: String, tier: Tier, needs: Set<GardenNeed>, howTo: String,
        caution: String = "", price: String = "", keywords: [String] = [], isUrine: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tier = tier
        self.needs = needs
        self.howTo = howTo
        self.caution = caution
        self.price = price
        self.keywords = keywords
        self.isUrine = isUrine
    }
}

public struct RankedOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tier: Tier
    public let howTo: String
    public let caution: String
    public let price: String
    /// The inventory item this suggestion uses, when the gardener already owns it.
    public let inventoryItemName: String?
}

public enum Toolbox {
    /// David never uses rock phosphate, blood meal, bone meal or other concentrated
    /// single-nutrient feeds, avoids salt fertilizers like calcium nitrate, and avoids chicken
    /// litter because of the arsenic (backend/persona/method.md), so none of these are offered
    /// here even when owned.
    static let avoided = [
        "blood meal", "bone meal", "rock phosphate", "feather meal", "bat guano", "sul-po-mag", "langbeinite",
        "calcium nitrate", "potassium nitrate", "ammonium nitrate", "sodium nitrate", "chilean nitrate", "ammonium sulfate",
        "chicken", "poultry",
    ]

    public static let options: [OrganicOption] = [
        // Feeding
        OrganicOption(
            id: "compost", name: "Compost or worm castings", tier: .free, needs: [.feed],
            howTo: "Side-dress about an inch of finished compost around the plant and scratch it in lightly, then water.",
            keywords: ["compost", "casting", "vermicompost"]
        ),
        OrganicOption(
            id: "manure", name: "Well-aged manure (cow, horse or rabbit)", tier: .free, needs: [.feed],
            howTo: "Side-dress about an inch of well-aged or composted manure around the plant and scratch it in lightly, then water.",
            caution: "Age it at least 4 to 6 months first. David avoids chicken litter because of the arsenic.", keywords: ["manure"]
        ),
        OrganicOption(
            id: "comfrey_tea", name: "Comfrey or weed tea", tier: .free, needs: [.feed],
            howTo: "Steep a bucket of comfrey or weed leaves in water for 2 to 3 weeks, dilute about 1 to 10, and pour it on the soil.",
            caution: "It smells strong; keep a lid on the bucket.", keywords: ["comfrey", "weed tea"]
        ),
        // Offered only when asked for (see `ranked`), never as the default suggestion.
        OrganicOption(
            id: "urine", name: "Diluted urine", tier: .free, needs: [.feed],
            howTo: "Mix 1 part fresh urine with 10 parts water and pour about a quart around each plant's root zone, not on the leaves.",
            caution: "Skip it on leafy greens and root crops within a month of harvest.", keywords: ["urine"], isUrine: true
        ),
        OrganicOption(
            id: "alfalfa", name: "Alfalfa pellets", tier: .lowCost, needs: [.feed],
            howTo: "Scratch in about a cup per plant (2 to 3 pounds per 100 sq ft) and water it in.",
            price: "about $20 to $30 for 40 to 50 lb at a feed store", keywords: ["alfalfa"]
        ),
        // David's own go-to feed (backend/persona/method.md): first among the products to buy.
        OrganicOption(
            id: "microlife", name: "MicroLife All Purpose granular (David's go-to)", tier: .branded, needs: [.feed],
            howTo: "Scratch it into the top inch around the plant at the bag's rate and water it in. At transplanting, mix a handful into each planting hole.",
            price: "roughly $30 to $60 for a 40 lb bag", keywords: ["microlife", "micro-life", "micro life"]
        ),
        // David's seedling and transplant spray. No keywords: owning one half isn't owning the mix.
        OrganicOption(
            id: "kelp_fish", name: "Liquid kelp and fish hydrolysate, mixed (David's spray)", tier: .branded, needs: [.foliar],
            howTo: "Mix both at their label's foliar rate in a small spray bottle and mist the leaves, tops and undersides. David does seedlings about once a week and keeps going for 2 or 3 weeks after transplanting.",
            price: "about $15 to $35 per quart of each"
        ),
        OrganicOption(
            id: "fish_emulsion", name: "Fish emulsion (e.g. Alaska 5-1-1)", tier: .branded, needs: [.feed],
            howTo: "Mix 1 tablespoon per gallon and water it in at the base.",
            caution: "Smells for a day and can attract animals.", price: "about $12 to $20 per quart",
            keywords: ["fish emulsion", "fish fertilizer", "alaska"]
        ),
        OrganicOption(
            id: "fish_seaweed", name: "Fish & seaweed blend (e.g. Neptune's Harvest)", tier: .branded, needs: [.feed, .foliar],
            howTo: "For feeding: 1 to 2 tablespoons per gallon at the base. For foliar: 1 tablespoon per gallon, coating the undersides of leaves until just dripping.",
            price: "about $20 to $35 per quart", keywords: ["neptune", "fish & seaweed", "fish and seaweed", "hydrolysate"]
        ),
        OrganicOption(
            id: "granular", name: "Balanced organic granular (e.g. Garden-tone, Tomato-tone, Dr. Earth)", tier: .branded, needs: [.feed],
            howTo: "Scratch in about 1/4 cup per plant (follow the bag) a few inches from the stem, then water.",
            caution: "Slow in cold soil.", price: "about $12 to $25 for 4 to 8 lb",
            keywords: ["garden-tone", "tomato-tone", "garden tone", "tomato tone", "plant-tone", "dr. earth", "dr earth", "granular"]
        ),

        // Foliar
        // No compost tea: David finds it more effort than result. Keep it simple.
        OrganicOption(
            id: "comfrey_foliar", name: "Comfrey tea, diluted", tier: .free, needs: [.foliar],
            howTo: "Dilute about 1 to 15, strain well, and spray leaves top and bottom.", keywords: ["comfrey"]
        ),
        OrganicOption(
            id: "kelp", name: "Liquid kelp (e.g. Maxicrop)", tier: .branded, needs: [.foliar],
            howTo: "1 tablespoon per gallon; coat the undersides of leaves until just dripping.",
            price: "about $15 to $30 per quart", keywords: ["kelp", "seaweed", "maxicrop"]
        ),
        OrganicOption(
            id: "fish_emulsion_foliar", name: "Fish emulsion, half strength", tier: .lowCost, needs: [.foliar],
            howTo: "About 1/2 tablespoon per gallon, sprayed on leaves top and bottom.",
            caution: "Smells for a day.", price: "about $12 to $20 per quart", keywords: ["fish emulsion", "alaska"]
        ),

        // Mulch
        OrganicOption(
            id: "leaves", name: "Aged or shredded leaves (oak is David's favorite)", tier: .free, needs: [.mulch],
            howTo: "Spread 2 to 3 inches, kept an inch or two off the stems.", keywords: ["leaves", "leaf mold"]
        ),
        OrganicOption(
            id: "grass", name: "Untreated grass clippings", tier: .free, needs: [.mulch],
            howTo: "Spread in thin layers, about an inch at a time, so they don't mat.",
            caution: "Only from lawns never treated with herbicide.", keywords: ["grass clipping"]
        ),
        OrganicOption(
            id: "straw", name: "Straw (not hay)", tier: .lowCost, needs: [.mulch],
            howTo: "Spread 3 to 4 inches loose; it settles to about 2.", price: "about $10 to $15 a bale", keywords: ["straw"]
        ),
        OrganicOption(
            id: "chips", name: "Arborist wood chips", tier: .free, needs: [.mulch],
            howTo: "Use on paths and around perennials, 2 to 3 inches deep; keep fresh chips off seedlings.",
            keywords: ["wood chip", "chips"]
        ),

        // Pests (organic, gentlest first)
        OrganicOption(
            id: "hand_pick", name: "Pick them off", tier: .free, needs: [.pests],
            howTo: "Knock beetles, caterpillars and egg clusters into a cup of soapy water; early morning, when they're sluggish, works best.",
            keywords: []
        ),
        OrganicOption(
            id: "water_blast", name: "A hard spray of water", tier: .free, needs: [.pests],
            howTo: "Blast aphids and mites off the stems and leaf undersides with the hose in the morning, every couple of days.",
            keywords: []
        ),
        OrganicOption(
            id: "insecticidal_soap", name: "Insecticidal soap (e.g. Safer Brand)", tier: .lowCost, needs: [.pests],
            howTo: "Spray soft-bodied pests like aphids directly, in the evening; it only works on contact.",
            caution: "Test a few leaves first on sensitive plants.", price: "about $8 to $12 a bottle",
            keywords: ["insecticidal soap", "safer"]
        ),
        OrganicOption(
            id: "bt", name: "Bt for caterpillars (e.g. Monterey B.t., Bonide Thuricide)", tier: .branded, needs: [.pests],
            howTo: "Spray leaves where caterpillars are feeding, in the evening; it affects only caterpillars.",
            price: "about $12 to $20", keywords: ["bt", "thuricide", "bacillus"]
        ),
        OrganicOption(
            id: "neem", name: "Neem oil (e.g. Garden Safe, Bonide)", tier: .branded, needs: [.pests],
            howTo: "Mix as the label says and spray at dusk, coating leaf undersides; repeat weekly while pests persist.",
            caution: "Spray only when bees aren't out, and not above about 90°F.", price: "about $10 to $18",
            keywords: ["neem"]
        ),

        // Frost
        OrganicOption(
            id: "sheets", name: "Old sheets or blankets", tier: .free, needs: [.frostCover],
            howTo: "Drape them over plants all the way to the ground in the evening, weigh down the edges, and take them off in the morning.",
            keywords: ["sheet", "blanket"]
        ),
        OrganicOption(
            id: "row_cover", name: "Frost cloth / row cover", tier: .lowCost, needs: [.frostCover],
            howTo: "Cover plants to the ground in the evening; it can stay on through a cold spell.",
            price: "about $10 to $25", keywords: ["row cover", "frost cloth", "frost blanket"]
        ),
    ]

    /// Inventory categories that can meet each need even when the product isn't in the list above.
    static func categories(for need: GardenNeed) -> Set<InventoryCategory> {
        switch need {
        case .feed: return [.fertilizer, .compost]
        case .foliar: return [.foliar]
        case .mulch: return [.mulch]
        case .frostCover: return []
        case .pests: return [.pestControl]
        }
    }

    /// Options for a need, in use-what-you-have order: owned, free, low cost, branded.
    /// Diluted urine is left out unless `includeUrine` is set (the gardener asked about it):
    /// it's one free option among several, not the default answer.
    public static func ranked(for need: GardenNeed, inventory: [InventoryInfo], includeUrine: Bool = false) -> [RankedOption] {
        let candidates = options.filter { $0.needs.contains(need) && (includeUrine || !$0.isUrine) }
        var owned: [RankedOption] = []
        var ownedOptionIDs: Set<String> = []

        for item in inventory {
            let lower = item.name.lowercased()
            // Even if they own one, David's method skips concentrated feeds, salts and chicken litter.
            if avoided.contains(where: { lower.contains($0) }) { continue }
            if let match = candidates.first(where: { opt in opt.keywords.contains(where: { lower.contains($0) }) }) {
                guard !ownedOptionIDs.contains(match.id) else { continue }
                ownedOptionIDs.insert(match.id)
                owned.append(RankedOption(
                    id: "owned-\(item.id.uuidString)", name: item.name, tier: .owned, howTo: match.howTo,
                    caution: match.caution, price: "", inventoryItemName: item.name
                ))
            } else if categories(for: need).contains(item.category) {
                owned.append(RankedOption(
                    id: "owned-\(item.id.uuidString)", name: item.name, tier: .owned,
                    howTo: "Use it as the label directs for this.", caution: "", price: "", inventoryItemName: item.name
                ))
            }
        }

        // Stable sort by tier, keeping the list's order within a tier.
        let rest = candidates
            .filter { !ownedOptionIDs.contains($0.id) }
            .enumerated()
            .sorted { ($0.element.tier.rank, $0.offset) < ($1.element.tier.rank, $1.offset) }
            .map { pair -> RankedOption in
                let o = pair.element
                return RankedOption(id: o.id, name: o.name, tier: o.tier, howTo: o.howTo, caution: o.caution, price: o.price, inventoryItemName: nil)
            }
        return owned + rest
    }
}
