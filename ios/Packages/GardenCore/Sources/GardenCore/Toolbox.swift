import Foundation

/// What a nudge is asking the gardener to supply.
public enum GardenNeed: String, Codable, Sendable {
    case feed
    case foliar
    case mulch
    case frostCover
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
    public static let options: [OrganicOption] = [
        // Feeding
        OrganicOption(
            id: "urine", name: "Diluted urine", tier: .free, needs: [.feed],
            howTo: "Mix 1 part fresh urine with 10 parts water and pour about a quart around each plant's root zone, not on the leaves.",
            caution: "Skip it on leafy greens and root crops within a month of harvest.", keywords: ["urine"], isUrine: true
        ),
        OrganicOption(
            id: "compost", name: "Compost or worm castings", tier: .free, needs: [.feed],
            howTo: "Side-dress about an inch of finished compost around the plant and scratch it in lightly, then water.",
            keywords: ["compost", "casting", "vermicompost"]
        ),
        OrganicOption(
            id: "comfrey_tea", name: "Comfrey or weed tea", tier: .free, needs: [.feed],
            howTo: "Steep a bucket of comfrey or weed leaves in water for 2 to 3 weeks, dilute about 1 to 10, and pour it on the soil.",
            caution: "It smells strong; keep a lid on the bucket.", keywords: ["comfrey", "weed tea"]
        ),
        OrganicOption(
            id: "alfalfa", name: "Alfalfa pellets", tier: .lowCost, needs: [.feed],
            howTo: "Scratch in about a cup per plant (2 to 3 pounds per 100 sq ft) and water it in.",
            price: "about $20 to $30 for 40 to 50 lb at a feed store", keywords: ["alfalfa"]
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
        OrganicOption(
            id: "blood_meal", name: "Blood meal (12-0-0)", tier: .branded, needs: [.feed],
            howTo: "About 1 tablespoon per plant scratched in and watered well.",
            caution: "Easy to overdo and burn plants; attracts dogs.", price: "about $12 to $20 for 3 lb", keywords: ["blood meal"]
        ),
        OrganicOption(
            id: "feather_meal", name: "Feather meal (slow nitrogen)", tier: .branded, needs: [.feed],
            howTo: "About 2 tablespoons per plant scratched in; it feeds for months.",
            price: "about $15 to $25 for 5 lb", keywords: ["feather meal"]
        ),

        // Foliar
        OrganicOption(
            id: "compost_tea", name: "Compost tea", tier: .free, needs: [.foliar],
            howTo: "Steep a shovelful of compost in a bucket of water overnight, strain through cloth, and spray leaves top and bottom.",
            keywords: ["compost tea"]
        ),
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
            id: "leaves", name: "Shredded leaves", tier: .free, needs: [.mulch],
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
        }
    }

    /// Options for a need, in use-what-you-have order: owned, free, low cost, branded.
    public static func ranked(for need: GardenNeed, inventory: [InventoryInfo], avoidUrine: Bool = false) -> [RankedOption] {
        let candidates = options.filter { $0.needs.contains(need) && !(avoidUrine && $0.isUrine) }
        var owned: [RankedOption] = []
        var ownedOptionIDs: Set<String> = []

        for item in inventory {
            let lower = item.name.lowercased()
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
