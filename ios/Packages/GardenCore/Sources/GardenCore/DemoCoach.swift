import Foundation

/// Offline stand-in for the coach, used until the backend is connected (and in previews).
/// It answers from the app's own rules and starter product list, and says plainly that it's a demo.
public enum DemoCoach {
    public static let notice = "(Demo mode: the live coach isn't connected yet, so this answer comes from the app's built-in rules.)"

    public static func reply(
        to question: String,
        state: GardenState,
        profile: GardenProfileInfo,
        now: Date,
        calendar: Calendar
    ) -> String {
        let q = question.lowercased()
        let today = LocalDay(now, calendar: calendar)
        let body: String

        if q.contains("frost") || q.contains("freeze") || q.contains("cold") {
            body = frostAnswer(state, today: today, calendar: calendar)
        } else if q.contains("foliar") || q.contains("spray") || q.contains("kelp") {
            body = optionsAnswer(
                lead: "For a foliar feed, spray early morning or evening when it's under about 85°F, calm, and no rain is due for a few hours. Coat the leaf undersides until just dripping.",
                need: .foliar, state: state, profile: profile
            )
        } else if q.contains("feed") || q.contains("fertiliz") || q.contains("nitrogen") || q.contains("yellow") {
            body = optionsAnswer(
                lead: "Feed the soil and the soil feeds the plant. Here's what I'd reach for, starting with what you have:",
                need: .feed, state: state, profile: profile
            )
        } else if q.contains("mulch") {
            body = optionsAnswer(
                lead: "Mulch keeps roots cool and cuts watering a lot. Keep it an inch or two off the stems.",
                need: .mulch, state: state, profile: profile
            )
        } else if q.contains("water") || q.contains("dry") || q.contains("wilt") {
            body = waterAnswer(state, today: today, calendar: calendar)
        } else if q.contains("stake") || q.contains("cage") || q.contains("trellis") {
            body = "Get supports in early, within a couple of weeks of planting, so you don't tear roots later. Set stakes 3 to 4 inches from the stem and tie loosely in a figure eight with soft ties or strips of old T-shirt."
        } else {
            body = "Ask me about watering, feeding, foliar sprays, mulch, staking or frost and I'll answer from what the app knows about your garden. For a full conversation, connect the live coach (Settings explains how)."
        }
        return "\(body)\n\n\(notice)"
    }

    static func optionsAnswer(lead: String, need: GardenNeed, state: GardenState, profile: GardenProfileInfo) -> String {
        let leafy = state.plants.contains { $0.crop.leafyOrRoot }
        let options = Toolbox.ranked(for: need, inventory: state.inventory, avoidUrine: profile.avoidUrine || (need == .feed && leafy))
        let lines = options.prefix(3).enumerated().map { i, o -> String in
            var line = "\(i + 1). \(o.name) (\(o.tier.displayName.lowercased())): \(o.howTo)"
            if !o.price.isEmpty { line += " About \(o.price.replacingOccurrences(of: "about ", with: ""))." }
            return line
        }
        return ([lead] + lines).joined(separator: "\n")
    }

    static func waterAnswer(_ state: GardenState, today: LocalDay, calendar: Calendar) -> String {
        guard state.weather != nil, !state.beds.isEmpty else {
            return "Do the finger test: push a finger 2 inches into the soil. Dry means water deeply, about an inch, slowly. Cool and damp means wait a day. Log it in the app so the water estimate learns your beds."
        }
        let lines = state.beds.map { bed -> String in
            let ws = WaterModel.state(
                bed: bed, plants: state.plants(in: bed), journal: state.journal, weather: state.weather, today: today, calendar: calendar
            )
            return "\(bed.name): \(ws.status.displayName.lowercased())"
        }
        return "Here's where I think your beds are, from the weather and your watering log:\n" + lines.joined(separator: "\n") +
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
                .init(tier: Tier.free.rawValue, title: "Diluted urine", how: "1 part to 10 parts water, about a quart at the base of each plant."),
                .init(tier: Tier.free.rawValue, title: "Compost side-dressing", how: "An inch around the plant, scratched in and watered."),
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
