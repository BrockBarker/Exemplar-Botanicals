import Foundation

/// Offline stand-in for the coach, used until the backend is connected (and in previews).
/// It answers from the app's own rules and starter product list, and says plainly that it's a demo.
public enum DemoCoach {
    public static let notice = "(Demo mode: the live coach isn't connected yet, so this answer comes from the app's built-in rules.)"

    /// `noted` is what the app just remembered from this message (see `SupplyMentions`); the
    /// reply confirms it, and answers only the part of the message that asks something.
    public static func reply(
        to question: String,
        state: GardenState,
        profile: GardenProfileInfo,
        now: Date,
        calendar: Calendar,
        noted: [CoachAction] = []
    ) -> String {
        let acknowledgment = SupplyMentions.acknowledgment(for: noted)
        let asked = acknowledgment == nil ? question : SupplyMentions.questionText(question)
        if let acknowledgment = acknowledgment, asked.isEmpty {
            return "\(acknowledgment)\n\n\(notice)"
        }
        let q = asked.lowercased()
        let today = LocalDay(now, calendar: calendar)
        func asks(_ words: String...) -> Bool { words.contains { q.contains($0) } }
        let body: String

        // David's own method first (backend/persona/method.md): starting transplants,
        // transplanting, building a raised bed and spacing.
        if asks(
            "start seeds", "starting seeds", "seed starting", "seed-starting", "seed tray", "grow transplants", "growing transplants",
            "start transplants", "starting transplants", "grow my own transplants", "sow indoors", "seedling mix", "potting mix"
        ) {
            body = seedStartAnswer
        } else if asks("transplant", "plant out", "planting out", "set out", "planting hole", "put them in the ground") {
            body = transplantAnswer
        } else if asks("bed"), asks("how big", "how wide", "how tall", "how deep", "how high", "what size", "dimensions", "how long") {
            body = bedSizeAnswer
        } else if asks(
            "build a raised bed", "building a raised bed", "fill a raised bed", "filling a raised bed", "fill my raised bed", "fill my bed",
            "fill the bed", "new raised bed", "make a raised bed", "set up a raised bed", "raised bed mix", "bed mix", "soil mix",
            "what soil", "what do i fill", "biochar", "azomite"
        ) {
            body = bedMixAnswer(state)
        } else if asks(
            "where should i put", "where to put", "where do i put", "where should i build", "where should the bed", "location",
            "best spot", "which direction", "facing", "how much sun", "afternoon shade", "full sun", "part shade", "siting"
        ) {
            body = sitingAnswer
        } else if asks("spacing", "how far apart", "space them", "space my", "how close", "how many plants per", "how many per") {
            body = spacingAnswer
        } else if asks("frost", "freeze", "cold snap") {
            body = frostAnswer(state, today: today, calendar: calendar)
        } else if asks("harvest", "ripe", "ready", "pick") {
            body = harvestAnswer(state, today: today, calendar: calendar)
        } else if asks("bug", "pest", "aphid", "beetle", "hornworm", "cabbage worm", "caterpillar", "holes in", "eating my", "slug", "mites") {
            body = pestAnswer(state)
        } else if asks("prune", "pruning", "sucker", "pinch", "deadhead", "trim") {
            body = pruneAnswer(state)
        } else if asks("sow", "succession", "plant more", "plant next", "what can i plant", "what should i plant") {
            body = sowAnswer(state)
        } else if asks("yellow") {
            body = yellowAnswer
        } else if asks("urine", "pee") {
            body = urineAnswer(state, profile: profile)
        } else if asks("foliar", "spray", "kelp") {
            body = optionsAnswer(
                lead: "For seedlings and new transplants, I keep it simple: liquid kelp and fish hydrolysate mixed in a small spray bottle, about once a week, and I keep going for 2 or 3 weeks after they're transplanted. Spray early morning or evening when it's under about 85°F, calm, and no rain is due for a few hours, and coat the leaf undersides. For established plants, every couple of weeks during active growth is plenty.",
                need: .foliar, state: state
            )
        } else if asks("feed", "fertiliz", "nitrogen", "compost") {
            body = optionsAnswer(
                lead: "Only feed what will use it: heavy feeders like tomatoes, squash and corn once they start flowering, and anything pale and slow-growing. Most crops do fine on compost-rich soil. When I do feed, it's mostly MicroLife All Purpose granular, plus a handful in each planting hole at transplanting. If something needs a boost, here's what I'd reach for, starting with what you have:",
                need: .feed, state: state
            )
        } else if asks("mulch") {
            body = optionsAnswer(
                lead: "My favorite mulch is aged oak leaves, but this is flexible: use what you can get. Mulch keeps roots cool and cuts watering a lot. Keep it an inch or two off the stems.",
                need: .mulch, state: state
            )
        } else if asks("water", "dry", "wilt") {
            body = waterAnswer(state, today: today, calendar: calendar)
        } else if asks("stake", "cage", "trellis") {
            body = "Get supports in early, within a couple of weeks of planting, so you don't tear roots later. Set stakes 3 to 4 inches from the stem and tie loosely in a figure eight with soft ties or strips of old T-shirt."
        } else {
            body = overviewAnswer(state, now: now, calendar: calendar)
        }
        if let acknowledgment = acknowledgment {
            return "\(acknowledgment)\n\n\(body)\n\n\(notice)"
        }
        return "\(body)\n\n\(notice)"
    }

    // MARK: David's method

    static let seedStartAnswer = """
    Here's how I grow my transplants:
    1. Sow into sifted compost with a bit of Azomite and MicroLife mixed in.
    2. Once they're up, foliar spray the seedlings about once a week with a simple mix of liquid kelp and fish hydrolysate in a small spray bottle (each at its label's foliar rate).
    3. When they go out, dig each hole, mix a handful of MicroLife into it, and keep up the weekly kelp and fish spray for another 2 or 3 weeks.
    """

    static let transplantAnswer = """
    When I transplant:
    1. Dig the hole for each plant and mix a handful of MicroLife into the hole.
    2. Give them extra-wide spacing, more room than the seed packet says, so each one can grow into an exemplary individual.
    3. Keep foliar spraying with a small bottle of liquid kelp and fish hydrolysate about once a week for another 2 or 3 weeks.
    4. Mulch with aged leaves. Oak is my favorite, but this is flexible.
    """

    static let bedSizeAnswer = """
    My beds are 5 feet wide, 2 feet tall and 10 to 12 feet long:
    1. The width helps them not dry out as fast.
    2. The height makes weeding super easy and gives the bed lots of oxygen and good drainage.
    """

    static let sitingAnswer = """
    Location is the thing I emphasize most when I help someone plan a garden:
    1. The best spot is between where you park your car and where you walk into your house, so you see it up close every day.
    2. In the northern hemisphere, face the bed south.
    3. In the hot, humid South, a bit of shade from the west in the afternoon helps, if you can get it.
    4. For winter growing, as much sun as possible.
    """

    static let wateringHabit = "I water regularly enough that plants never wilt. Early in a plant's life I water nearly every day so it isn't stressed at all, and I slack off once it's established."

    static let spacingAnswer = "I give everything extra-wide spacing, more room than the seed packet says rather than less, so each plant can grow into an exemplary individual. Crowded plants fight over water and food and get less airflow, which invites disease."

    static func bedMixAnswer(_ state: GardenState) -> String {
        var text = """
        Here's how I build a raised bed:
        First, the spot: location matters most. Put it between where you park and your front door so you see it every day, face it south, give it a bit of west afternoon shade if you're in the hot, humid South, and as much sun as you can get for winter growing.
        My beds are 5 feet wide, 2 feet tall and 10 to 12 feet long.
        1. The base mix is about half silty topsoil and half aged wood chips or finished compost.
        2. Then as much biochar as I can get, up to about 10% of the mix at most, and a fair amount of Azomite.
        3. Extras if I've got them: fresh kitchen scraps mixed in, lots of bones from bone broth, pretty much any green organic matter. I'm not against putting a piece of roadkill down in the bed; bury it deep at the bottom and wear gloves.
        None of the extras are entirely necessary. Topsoil plus wood chips or compost makes a good bed on its own. Then plant with extra-wide spacing and mulch with aged leaves.
        """
        let useful = ["compost", "wood chip", "biochar", "azomite", "kitchen scrap", "bone", "manure", "topsoil", "casting"]
        let have = state.inventory.map { $0.name }.filter { name in useful.contains { name.lowercased().contains($0) } }
        if !have.isEmpty {
            text += "\nFrom what you've told me, you already have \(SupplyMentions.listed(have.map { SupplyMentions.proseName($0) ?? $0 })) to work with."
        }
        return text
    }

    /// "What should I be doing?": the most useful things this week, across the whole garden.
    static func overviewAnswer(_ state: GardenState, now: Date, calendar: Calendar) -> String {
        guard !state.plants.isEmpty else {
            return "Add your beds and plants in the Garden tab and I'll keep track of what needs doing as the season goes: watering, harvests, pest checks, pruning, sowing and frost."
        }
        var kinds: Set<NudgeKind> = []
        let top = NudgeEngine(settings: .standard, calendar: calendar)
            .candidates(state, now: now)
            .sorted { $0.priority > $1.priority }
            .filter { kinds.insert($0.kind).inserted }
            .prefix(4)
        guard !top.isEmpty else {
            return "Nothing pressing this week. It's a good time to walk the garden, pull a few weeds while they're small, and take a progress photo of each bed."
        }
        let lines = top.enumerated().map { "\($0.offset + 1). \($0.element.title). \($0.element.body)" }
        return (["Here's what I'd do this week:"] + lines).joined(separator: "\n")
    }

    static func harvestAnswer(_ state: GardenState, today: LocalDay, calendar: Calendar) -> String {
        guard !state.plants.isEmpty else {
            return "Add your plants with their planting dates in the Garden tab and I'll tell you when each one should be ready and how to tell."
        }
        var lines: [String] = []
        for plant in state.plants where plant.stage != .seed && plant.stage != .dormant {
            let care = plant.crop.care
            if plant.stage == .mature || (plant.stage == .fruiting && care.pickEveryDays != nil) {
                lines.append("\(plant.name): pick when \(care.readyWhen).")
            } else if let start = care.firstHarvestDays, let planted = plant.plantedOn {
                let left = start - planted.days(to: today, calendar: calendar)
                if left <= 0 {
                    lines.append("\(plant.name): should be ready about now. It's ready when \(care.readyWhen).")
                } else {
                    lines.append("\(plant.name): about \(left) days to go (usually around day \(start)).")
                }
            } else if care.firstHarvestDays != nil {
                lines.append("\(plant.name): add its planting date and I can estimate it. It's ready when \(care.readyWhen).")
            }
        }
        guard !lines.isEmpty else {
            return "Nothing's close to harvest yet. I'll remind you as each crop gets near."
        }
        return (["Here's where your harvests stand:"] + lines + ["Pick in the cool of the morning, and log harvests so I know when to remind you again."])
            .joined(separator: "\n")
    }

    static func pestAnswer(_ state: GardenState) -> String {
        var seen: Set<String> = []
        let watch = state.plants
            .filter { $0.crop.care.watchFor != nil && seen.insert($0.crop.id).inserted }
            .map { "\($0.name): \($0.crop.care.watchFor ?? "")." }
        let options = Toolbox.ranked(for: .pests, inventory: state.inventory).prefix(4).enumerated().map { i, o -> String in
            var line = "\(i + 1). \(o.name) (\(o.tier.displayName.lowercased())): \(o.howTo)"
            if !o.price.isEmpty { line += " About \(o.price.replacingOccurrences(of: "about ", with: ""))." }
            return line
        }
        var parts: [String] = []
        if !watch.isEmpty { parts.append((["What to look for on your plants:"] + watch).joined(separator: "\n")) }
        parts.append((["If you find some, start gentle:"] + options).joined(separator: "\n"))
        parts.append("Spray only in the evening when bees aren't out, and only the plants that need it. A photo in the Photo check tab helps if you're not sure what you're seeing.")
        return parts.joined(separator: "\n\n")
    }

    static func pruneAnswer(_ state: GardenState) -> String {
        var seen: Set<String> = []
        let lines = state.plants
            .filter { $0.crop.care.prune != nil && seen.insert($0.crop.id).inserted }
            .map { "\($0.name): \($0.crop.care.prune ?? "")" }
        let general = "Most vegetables need little pruning. Take off yellowing or diseased leaves, keep leaves off the soil, and use clean snips on a dry day."
        guard !lines.isEmpty else { return general }
        return (["Here's the pruning worth doing in your garden:"] + lines + [general]).joined(separator: "\n")
    }

    static func sowAnswer(_ state: GardenState) -> String {
        var seen: Set<String> = []
        let lines = state.plants
            .filter { $0.crop.care.sowAgainDays != nil && seen.insert($0.crop.id).inserted }
            .map { plant -> String in
                let care = plant.crop.care
                var text = "\(plant.crop.name): a short row every \(care.sowAgainDays ?? 14) days"
                if let days = care.firstHarvestDays { text += ", ready in about \(days) days" }
                return text + "."
            }
        let general = "Quick crops like lettuce, radishes, bush beans, cilantro and basil do best sown a little at a time, so you get a steady supply instead of a glut. Lettuce and spinach like it cool; beans and basil like it warm."
        guard !lines.isEmpty else { return general }
        return (["Sow a little at a time:"] + lines + [general]).joined(separator: "\n")
    }

    static let yellowAnswer = """
        Yellow leaves have a few usual causes, and feeding isn't always the fix:
        1. The oldest leaves yellow first, evenly: often nitrogen running low, or just old leaves being shed late in the season. If the whole plant is pale and slow, side-dress with compost.
        2. Yellow between the veins on new growth: usually a pH problem locking out iron. A soil test can confirm it if you want to be sure, though I've never needed one for my own beds.
        3. Yellow and droopy with soggy soil: too much water. Let it dry out 2 inches down before watering again.
        4. Yellow with brown spots or rings: likely a leaf disease such as early blight. Pick off the affected leaves and keep water off the foliage.
        A photo in the Photo check tab helps tell them apart.
        """

    static func urineAnswer(_ state: GardenState, profile: GardenProfileInfo) -> String {
        if profile.avoidUrine {
            return "You've asked me to leave urine out, so I will. Compost or worm castings, side-dressed about an inch deep, does the same job more gently."
        }
        let leafy = state.plants.contains { $0.crop.leafyOrRoot }
        var text = "Diluted urine is a free, fast nitrogen source: about 1 part to 10 parts water, a quart around the base of a plant, on the soil and never the leaves. It suits hungry crops like tomatoes, squash and corn once they're growing hard; it's no help to beans and peas, which make their own nitrogen. Use it now and then, not every week."
        if leafy { text += " Keep it off leafy greens and root crops for the last month before harvest." }
        return text
    }

    static func optionsAnswer(lead: String, need: GardenNeed, state: GardenState) -> String {
        let options = Toolbox.ranked(for: need, inventory: state.inventory)
        let lines = options.prefix(3).enumerated().map { i, o -> String in
            var line = "\(i + 1). \(o.name) (\(o.tier.displayName.lowercased())): \(o.howTo)"
            if !o.price.isEmpty { line += " About \(o.price.replacingOccurrences(of: "about ", with: ""))." }
            return line
        }
        return ([lead] + lines).joined(separator: "\n")
    }

    static func waterAnswer(_ state: GardenState, today: LocalDay, calendar: Calendar) -> String {
        guard state.weather != nil, !state.beds.isEmpty else {
            return "\(Self.wateringHabit)\n\nDo the finger test: push a finger 2 inches into the soil. Dry means water deeply, about an inch, slowly. Cool and damp means wait a day. Log it in the app so the water estimate learns your beds."
        }
        let lines = state.beds.map { bed -> String in
            let ws = WaterModel.state(
                bed: bed, plants: state.plants(in: bed), journal: state.journal, weather: state.weather, today: today, calendar: calendar
            )
            return "\(bed.name): \(ws.status.displayName.lowercased())"
        }
        return Self.wateringHabit + "\n\nHere's where I think your beds are, from the weather and your watering log:\n" + lines.joined(separator: "\n") +
            "\nWhen in doubt, the finger test wins: dry 2 inches down means water deeply."
    }

    static func frostAnswer(_ state: GardenState, today: LocalDay, calendar: Calendar) -> String {
        let cold = state.weather?.days
            .filter { $0.day >= today && $0.day <= today.adding(days: 6, calendar: calendar) }
            .compactMap { d -> (LocalDay, Double)? in
                guard let low = d.lowF, low <= 36 else { return nil }
                return (d.day, low)
            }
            .first
        let cover = Toolbox.ranked(for: .frostCover, inventory: state.inventory).first
        let how = cover.map { "\($0.name): \($0.howTo)" } ?? "Cover plants to the ground in the evening."
        if let found = cold {
            let (day, low) = found
            let name = day.adding(days: -1, calendar: calendar).spokenName(relativeTo: today, calendar: calendar)
            return "The forecast shows a low near \(NudgeText.temp(low)), so cover tender plants \(name == "today" ? "tonight" : "\(name) night"). \(how) Water the soil that afternoon; moist soil holds heat."
        }
        return "No frost in the next week's forecast. When one comes, the app will remind you the afternoon before. \(how)"
    }

    /// A sample result so the diagnosis screen can be tried without the backend.
    public static func diagnosis(plantName: String) -> Diagnosis {
        let plant = plantName.isEmpty ? "this plant" : plantName
        return Diagnosis(
            summary: "Demo result: the live coach isn't connected, so this is an example of what a diagnosis looks like, not a real look at \(plant).",
            overall: DiagnosisOverall.nutrientDeficiency.rawValue,
            confidence: DiagnosisConfidence.low.rawValue,
            findings: [
                .init(issue: "Example: nitrogen deficiency", category: FindingCategory.deficiency.rawValue, nutrient: "nitrogen",
                      likelihood: FindingLikelihood.possible.rawValue,
                      evidence: "In a real diagnosis this explains what in the photo points here, like even yellowing on the oldest leaves."),
                .init(issue: "Example: underwatering", category: FindingCategory.underwatering.rawValue,
                      likelihood: FindingLikelihood.unlikely.rawValue, evidence: "Alternatives are listed with how likely each one is."),
            ],
            fixes: [
                .init(tier: Tier.free.rawValue, title: "Compost side-dressing", how: "An inch around the plant, scratched in and watered."),
                .init(tier: Tier.free.rawValue, title: "Comfrey or weed tea", how: "Steeped 2 to 3 weeks, diluted about 1 to 10, poured on the soil."),
                .init(tier: Tier.branded.rawValue, title: "Fish emulsion", how: "1 tablespoon per gallon, watered in at the base.",
                      product: "Alaska Fish Fertilizer 5-1-1", price: "about $12 to $20 per quart",
                      pros: "Fast-acting and gentle.", cons: "Smells for a day."),
            ],
            soilTestSuggested: true,
            soilTestReason: "In a real diagnosis, a soil test is suggested when a deficiency and a pH problem look alike.",
            followUp: "Connect the live coach to get a real diagnosis of your photo.",
            journalNote: "",
            photoQualityNote: ""
        )
    }
}
