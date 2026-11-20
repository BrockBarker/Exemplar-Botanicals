import Foundation

/// Season-long care for a crop beyond water and food: when and how to harvest, what to scout
/// for, pruning, and succession sowing. Starter values from mainstream US extension guidance;
/// David can tune them.
public struct CropCare: Hashable, Sendable {
    /// Typical days from planting (the usual way: transplants for tomatoes, peppers, eggplant,
    /// cabbage-family and onions; seed for the rest) to the first harvest. Nil for perennials,
    /// where the growth stage tells instead.
    public let firstHarvestDays: Int?
    /// How to tell it's ready, as a clause: "the fruit is fully colored and gives a little".
    public let readyWhen: String
    /// Keeps producing: pick about this often once harvest starts. Nil means a one-time harvest.
    public let pickEveryDays: Int?
    /// Pests or problems worth a regular look, as a clause.
    public let watchFor: String?
    /// Routine pruning, pinching or deadheading, as a sentence.
    public let prune: String?
    public let pruneEveryDays: Int?
    /// Sow a little more this often for a steady supply.
    public let sowAgainDays: Int?

    public init(
        firstHarvestDays: Int?, readyWhen: String, pickEveryDays: Int? = nil, watchFor: String? = nil,
        prune: String? = nil, pruneEveryDays: Int? = nil, sowAgainDays: Int? = nil
    ) {
        self.firstHarvestDays = firstHarvestDays
        self.readyWhen = readyWhen
        self.pickEveryDays = pickEveryDays
        self.watchFor = watchFor
        self.prune = prune
        self.pruneEveryDays = pruneEveryDays
        self.sowAgainDays = sowAgainDays
    }

    public static let unknown = CropCare(firstHarvestDays: nil, readyWhen: "it looks and tastes the way you like it")
}

public extension CropProfile {
    var care: CropCare { CropCatalog.care(for: id) }
}

public extension CropCatalog {
    static func care(for id: String?) -> CropCare {
        guard let id = id, let care = careByID[id] else { return .unknown }
        return care
    }

    /// Keyed by crop id; every id in `all` has an entry.
    static let careByID: [String: CropCare] = [
        "tomato": CropCare(
            firstHarvestDays: 70, readyWhen: "the fruit is fully colored and gives a little when squeezed (pick at first blush if critters or splitting are a problem and let it ripen on the counter)",
            pickEveryDays: 3, watchFor: "hornworms (big green caterpillars; look for black droppings on the leaves) and brown spotted lower leaves from early blight",
            prune: "Pinch out suckers below the first flower cluster and remove lower leaves that touch the soil.", pruneEveryDays: 10
        ),
        "cherry_tomato": CropCare(
            firstHarvestDays: 60, readyWhen: "they're fully colored and come off with a gentle tug (pick before a heavy rain so they don't split)",
            pickEveryDays: 2, watchFor: "hornworms (look for black droppings on the leaves) and spotted lower leaves",
            prune: "Pinch out suckers below the first flower cluster and remove lower leaves that touch the soil.", pruneEveryDays: 10
        ),
        "pepper": CropCare(
            firstHarvestDays: 70, readyWhen: "they're full size and firm (green is fine to eat; wait for full color for sweetness)",
            pickEveryDays: 5, watchFor: "aphids under the leaves"
        ),
        "eggplant": CropCare(
            firstHarvestDays: 70, readyWhen: "the skin is glossy and springs back when pressed (dull skin means it's past its best)",
            pickEveryDays: 4, watchFor: "flea beetles (tiny shot holes in the leaves)"
        ),
        "cucumber": CropCare(
            firstHarvestDays: 55, readyWhen: "they're 4 to 8 inches long, firm and still green (yellow means overripe)",
            pickEveryDays: 2, watchFor: "cucumber beetles (yellow with black stripes or spots)"
        ),
        "summer_squash": CropCare(
            firstHarvestDays: 50, readyWhen: "they're 6 to 8 inches long; they grow fast, so check every day or two",
            pickEveryDays: 2, watchFor: "squash bugs and their bronze egg clusters under the leaves, and sawdust-like frass at the base of the stem from vine borers"
        ),
        "winter_squash": CropCare(
            firstHarvestDays: 95, readyWhen: "the rind is too hard to dent with a fingernail and the stem has turned corky (cut with 2 inches of stem and cure a week in the sun)",
            watchFor: "squash bugs and their bronze egg clusters under the leaves"
        ),
        "melon": CropCare(
            firstHarvestDays: 80, readyWhen: "a cantaloupe slips off the vine with light pressure and smells sweet, or a watermelon's ground spot turns creamy yellow and the nearest tendril dries",
            pickEveryDays: 3, watchFor: "cucumber beetles"
        ),
        "corn": CropCare(
            firstHarvestDays: 75, readyWhen: "the silks are brown and dry and a kernel pierced with a fingernail gives milky juice",
            watchFor: "corn earworms at the tip of the ear"
        ),
        "bush_bean": CropCare(
            firstHarvestDays: 55, readyWhen: "the pods snap cleanly and the beans inside are still small; picking often keeps them coming",
            pickEveryDays: 3, watchFor: "Mexican bean beetles (spiny yellow larvae under the leaves)", sowAgainDays: 21
        ),
        "pole_bean": CropCare(
            firstHarvestDays: 65, readyWhen: "the pods snap cleanly and the beans inside are still small; picking often keeps them coming",
            pickEveryDays: 3, watchFor: "Mexican bean beetles (spiny yellow larvae under the leaves)"
        ),
        "pea": CropCare(
            firstHarvestDays: 60, readyWhen: "shelling peas are plump in the pod, or snow peas are full length but still flat",
            pickEveryDays: 3, watchFor: "aphids on the growing tips"
        ),
        "lettuce": CropCare(
            firstHarvestDays: 45, readyWhen: "outer leaves are about 4 inches long (pick those and leave the center), or heads are firm; cut before it stretches upward and turns bitter",
            pickEveryDays: 5, watchFor: "slugs (ragged holes, slime trails) and aphids", sowAgainDays: 14
        ),
        "spinach": CropCare(
            firstHarvestDays: 40, readyWhen: "leaves are 3 to 4 inches long; harvest before warm weather makes it bolt",
            pickEveryDays: 5, watchFor: "leaf miners (pale winding tunnels in the leaves)", sowAgainDays: 14
        ),
        "kale": CropCare(
            firstHarvestDays: 55, readyWhen: "the lower leaves are about hand-sized (pick from the bottom up and leave the top growing)",
            pickEveryDays: 7, watchFor: "cabbage worms (velvety green caterpillars) and aphids under the leaves"
        ),
        "chard": CropCare(
            firstHarvestDays: 55, readyWhen: "the outer stalks are 8 to 10 inches tall (cut those at the base and leave the center)",
            pickEveryDays: 7, watchFor: "leaf miners (pale tunnels in the leaves)"
        ),
        "cabbage": CropCare(
            firstHarvestDays: 70, readyWhen: "the head is firm when squeezed; cut it before it splits",
            watchFor: "cabbage worms (velvety green caterpillars)"
        ),
        "broccoli": CropCare(
            firstHarvestDays: 60, readyWhen: "the head is tight and dark green, before any yellow flowers open; side shoots follow for weeks",
            pickEveryDays: 5, watchFor: "cabbage worms (velvety green caterpillars)"
        ),
        "cauliflower": CropCare(
            firstHarvestDays: 60, readyWhen: "the head is 6 to 8 inches across and still tight",
            watchFor: "cabbage worms (velvety green caterpillars)"
        ),
        "carrot": CropCare(
            firstHarvestDays: 70, readyWhen: "the shoulders at the soil line are about 3/4 inch across (pull one to check)",
            sowAgainDays: 21
        ),
        "beet": CropCare(
            firstHarvestDays: 55, readyWhen: "the roots are 1½ to 3 inches across (the greens are good to eat too)",
            sowAgainDays: 21
        ),
        "radish": CropCare(
            firstHarvestDays: 25, readyWhen: "the roots are about an inch across; they turn pithy fast if left",
            sowAgainDays: 10
        ),
        "onion": CropCare(
            firstHarvestDays: 100, readyWhen: "the tops flop over and start to yellow (pull them and cure in the shade for two weeks)"
        ),
        "garlic": CropCare(
            firstHarvestDays: 240, readyWhen: "a third to half of the leaves have browned (dig, don't pull, and cure two to three weeks); cut the curly scapes in early summer"
        ),
        "potato": CropCare(
            firstHarvestDays: 90, readyWhen: "new potatoes are ready when the plants flower; for storage potatoes, wait two weeks after the vines die back",
            watchFor: "Colorado potato beetles (striped adults, orange egg clusters under the leaves)"
        ),
        "sweet_potato": CropCare(
            firstHarvestDays: 100, readyWhen: "the roots are a good size when you feel around the base; dig before frost and cure somewhere warm for a week"
        ),
        "okra": CropCare(
            firstHarvestDays: 55, readyWhen: "the pods are 2 to 4 inches long; bigger ones turn woody, so check every day or two",
            pickEveryDays: 2, watchFor: "aphids and stink bugs"
        ),
        "strawberry": CropCare(
            firstHarvestDays: nil, readyWhen: "the berries are red right up to the shoulders",
            pickEveryDays: 2, watchFor: "slugs and birds"
        ),
        "blueberry": CropCare(
            firstHarvestDays: nil, readyWhen: "the berries have been fully blue for a few days and drop into your hand",
            pickEveryDays: 4, watchFor: "birds (net the bushes as the berries color)"
        ),
        "bramble": CropCare(
            firstHarvestDays: nil, readyWhen: "the berries are deeply colored and pull off easily",
            pickEveryDays: 3, watchFor: "Japanese beetles and soft, leaky berries from spotted wing drosophila",
            prune: "Once a cane has finished fruiting, cut it to the ground to make room for new ones.", pruneEveryDays: 30
        ),
        "basil": CropCare(
            firstHarvestDays: 30, readyWhen: "it's about 6 inches tall (pinch the top pair of leaves just above a leaf joint so it branches)",
            pickEveryDays: 7, watchFor: "slugs and Japanese beetles",
            prune: "Pinch off flower buds as soon as they appear so the leaves stay sweet.", pruneEveryDays: 7, sowAgainDays: 21
        ),
        "perennial_herb": CropCare(
            firstHarvestDays: nil, readyWhen: "it's growing well (cut sprigs any time, up to a third of the plant)",
            prune: "Trim back by about a third after flowering to keep it bushy and stop it going woody.", pruneEveryDays: 45
        ),
        "annual_herb": CropCare(
            firstHarvestDays: 40, readyWhen: "the plants are 6 inches tall (cut the outer stems; cilantro bolts fast in heat)",
            pickEveryDays: 7, sowAgainDays: 21
        ),
        "flower_annual": CropCare(
            firstHarvestDays: 60, readyWhen: "the blooms are just opening (cut in the cool of the morning)",
            pickEveryDays: 7, prune: "Deadhead spent blooms so the plants keep flowering.", pruneEveryDays: 7
        ),
        "dahlia": CropCare(
            firstHarvestDays: 90, readyWhen: "the blooms are nearly fully open (they don't open further once cut)",
            pickEveryDays: 4, watchFor: "earwigs and slugs",
            prune: "Pinch the center tip once at about a foot tall for bushier plants, then deadhead spent blooms.", pruneEveryDays: 10
        ),
        "rose": CropCare(
            firstHarvestDays: nil, readyWhen: "the buds are showing color and just starting to open",
            watchFor: "Japanese beetles and black spot on the leaves",
            prune: "Deadhead spent blooms back to the first leaf with five leaflets.", pruneEveryDays: 10
        ),
        "fruit_tree": CropCare(
            firstHarvestDays: nil, readyWhen: "the fruit comes away with a gentle lift and twist",
            watchFor: "fallen fruit (pick it up so pests don't overwinter in it)"
        ),
        "citrus": CropCare(
            firstHarvestDays: nil, readyWhen: "the fruit is fully colored and tastes sweet (color alone can fool you, so taste one)",
            watchFor: "scale and aphids on the undersides of leaves"
        ),
    ]
}
