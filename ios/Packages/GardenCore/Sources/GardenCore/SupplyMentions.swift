import Foundation

/// Picks up what the gardener tells the coach they have on hand ("I've got a bag of alfalfa
/// pellets", "we ran out of fish emulsion", "my budget is $30 a month"), so the built-in demo
/// coach remembers it across chats the way the live coach does with update_inventory.
///
/// It's deliberately cautious: it only reacts to first-person statements ("I have", "I bought",
/// "I'm out of") that name a supply it knows, and skips "if" and "should I" sentences.
public enum SupplyMentions {
    public struct Supply: Sendable {
        public let name: String
        public let category: InventoryCategory
        /// Lowercased phrases that name it; matched as whole words (a trailing "s" is fine).
        let phrases: [String]

        /// The name as it reads mid-sentence ("fish emulsion", "Bt", "Garden-tone").
        var prose: String {
            guard let first = name.first, first.isUppercase else { return name }
            let rest = name.dropFirst()
            // Brand names and abbreviations keep their capital.
            if Self.keepsCapital.contains(name) || rest.first?.isUppercase == true { return name }
            return first.lowercased() + rest
        }

        static let keepsCapital: Set<String> = [
            "Bt", "Garden-tone", "Tomato-tone", "Plant-tone", "Dr. Earth fertilizer", "Neptune's Harvest fish & seaweed",
            "Alaska fish fertilizer", "Maxicrop liquid kelp", "Safer insecticidal soap", "Azomite", "MicroLife All Purpose",
        ]
    }

    public static let supplies: [Supply] = [
        // Feeding and soil
        Supply(name: "Compost", category: .compost, phrases: ["compost", "compost pile", "compost bin", "finished compost"]),
        Supply(name: "Worm castings", category: .compost, phrases: ["worm castings", "castings", "vermicompost", "worm bin"]),
        Supply(name: "Compost tea", category: .foliar, phrases: ["compost tea"]),
        Supply(name: "Comfrey", category: .fertilizer, phrases: ["comfrey", "comfrey tea"]),
        Supply(name: "Alfalfa pellets", category: .fertilizer, phrases: ["alfalfa", "alfalfa pellets", "alfalfa meal", "rabbit food pellets"]),
        Supply(name: "Fish emulsion", category: .fertilizer, phrases: ["fish emulsion", "fish fertilizer"]),
        Supply(name: "Alaska fish fertilizer", category: .fertilizer, phrases: ["alaska fish fertilizer", "alaska fish emulsion", "alaska fish"]),
        Supply(name: "Neptune's Harvest fish & seaweed", category: .foliar, phrases: ["neptune's harvest", "neptunes harvest", "fish and seaweed", "fish & seaweed"]),
        Supply(name: "Fish hydrolysate", category: .foliar, phrases: ["fish hydrolysate", "hydrolyzed fish"]),
        Supply(name: "Liquid kelp", category: .foliar, phrases: ["kelp", "liquid kelp", "seaweed extract", "liquid seaweed"]),
        Supply(name: "Maxicrop liquid kelp", category: .foliar, phrases: ["maxicrop"]),
        Supply(name: "Kelp meal", category: .amendment, phrases: ["kelp meal"]),
        Supply(name: "MicroLife All Purpose", category: .fertilizer, phrases: ["microlife", "micro-life", "micro life"]),
        Supply(name: "Garden-tone", category: .fertilizer, phrases: ["garden-tone", "garden tone", "gardentone"]),
        Supply(name: "Tomato-tone", category: .fertilizer, phrases: ["tomato-tone", "tomato tone", "tomatotone"]),
        Supply(name: "Plant-tone", category: .fertilizer, phrases: ["plant-tone", "plant tone", "planttone"]),
        Supply(name: "Dr. Earth fertilizer", category: .fertilizer, phrases: ["dr earth", "doctor earth"]),
        Supply(name: "Blood meal", category: .fertilizer, phrases: ["blood meal"]),
        Supply(name: "Feather meal", category: .fertilizer, phrases: ["feather meal"]),
        Supply(name: "Bone meal", category: .fertilizer, phrases: ["bone meal"]),
        Supply(name: "Manure", category: .compost, phrases: ["manure", "aged manure", "chicken manure", "horse manure", "cow manure", "rabbit manure"]),
        Supply(name: "Coffee grounds", category: .compost, phrases: ["coffee grounds", "used coffee"]),
        Supply(name: "Kitchen scraps", category: .compost, phrases: ["kitchen scraps", "food scraps", "veggie scraps", "vegetable scraps"]),
        Supply(name: "Wood ash", category: .amendment, phrases: ["wood ash", "wood ashes", "fireplace ash", "fireplace ashes"]),
        Supply(name: "Eggshells", category: .amendment, phrases: ["eggshell", "egg shell"]),
        Supply(name: "Garden lime", category: .amendment, phrases: ["garden lime", "dolomite lime", "dolomitic lime", "pelletized lime", "agricultural lime"]),
        Supply(name: "Gypsum", category: .amendment, phrases: ["gypsum"]),
        Supply(name: "Rock dust", category: .rockDust, phrases: ["rock dust", "basalt dust", "greensand"]),
        Supply(name: "Azomite", category: .rockDust, phrases: ["azomite"]),
        Supply(name: "Biochar", category: .amendment, phrases: ["biochar", "bio-char", "bio char"]),
        Supply(name: "Broth bones", category: .amendment, phrases: ["bones from bone broth", "broth bones", "soup bones", "leftover bones"]),
        Supply(name: "Topsoil", category: .amendment, phrases: ["topsoil", "top soil"]),
        Supply(name: "Mycorrhizal inoculant", category: .biological, phrases: ["mycorrhizae", "mycorrhizal", "myco"]),
        // Mulch
        Supply(name: "Shredded leaves", category: .mulch, phrases: ["shredded leaves", "leaf pile", "pile of leaves", "bags of leaves", "bag of leaves", "fall leaves", "leaf mold", "oak leaves", "aged leaves"]),
        Supply(name: "Grass clippings", category: .mulch, phrases: ["grass clippings", "lawn clippings"]),
        Supply(name: "Straw", category: .mulch, phrases: ["straw", "straw bale", "bale of straw"]),
        Supply(name: "Wood chips", category: .mulch, phrases: ["wood chips", "arborist chips", "chip mulch"]),
        // Pest control
        Supply(name: "Insecticidal soap", category: .pestControl, phrases: ["insecticidal soap"]),
        Supply(name: "Safer insecticidal soap", category: .pestControl, phrases: ["safer soap", "safer brand", "safer insecticidal soap"]),
        Supply(name: "Neem oil", category: .pestControl, phrases: ["neem", "neem oil"]),
        Supply(name: "Bt", category: .pestControl, phrases: ["bt", "thuricide", "bacillus thuringiensis", "monterey bt"]),
        Supply(name: "Diatomaceous earth", category: .pestControl, phrases: ["diatomaceous earth"]),
        // Tools and covers
        Supply(name: "Row cover", category: .tool, phrases: ["row cover", "frost cloth", "frost blanket", "garden fabric"]),
        Supply(name: "Old sheets or blankets", category: .tool, phrases: ["old sheets", "old blankets", "bed sheets", "bedsheets"]),
        Supply(name: "Rain barrel", category: .tool, phrases: ["rain barrel", "rain tank"]),
        Supply(name: "Soaker hose", category: .tool, phrases: ["soaker hose", "drip irrigation", "drip line", "drip system"]),
        Supply(name: "Sprayer", category: .tool, phrases: ["sprayer", "pump sprayer", "spray bottle"]),
    ]

    // MARK: - Reading a message

    /// Inventory and budget changes stated in a message, ready for the app's ActionApplier.
    public static func actions(from message: String) -> [CoachAction] {
        var byName: [String: CoachAction] = [:]
        var order: [String] = []
        var budget: CoachAction?

        for sentence in sentences(message) {
            let text = sentence.text
            if skips.contains(where: { text.contains($0) }) { continue }
            let masked = notStatements.reduce(text) { $0.replacingOccurrences(of: $1, with: "#") }
            let negative = negativeCues.contains { masked.contains($0) }
            let cues = sentence.isQuestion ? questionCues : positiveCues
            let positive = cues.contains { masked.contains($0) }

            if negative || positive {
                for supply in supplies(in: text) {
                    var action = CoachAction(
                        type: .inventory,
                        summary: negative ? "Noted you're out of \(supply.prose)" : "Remembered you have \(supply.prose)"
                    )
                    action.action = negative ? "remove" : "add"
                    action.name = supply.name
                    action.category = supply.category.rawValue
                    if byName[supply.name] == nil { order.append(supply.name) }
                    byName[supply.name] = action
                }
            }
            if !sentence.isQuestion, let dollars = monthlyBudget(in: text) {
                var action = CoachAction(type: .budget, summary: "Remembered your budget: about $\(Int(dollars.rounded())) a month")
                action.monthlyDollars = dollars
                budget = action
            }
        }
        return order.compactMap { byName[$0] } + (budget.map { [$0] } ?? [])
    }

    /// The parts of a message that ask something, for picking a topic to answer.
    public static func questionText(_ message: String) -> String {
        sentences(message).filter { $0.isQuestion }.map { $0.text }.joined(separator: " ")
    }

    /// One or two sentences confirming what was remembered, in the coach's voice.
    public static func acknowledgment(for actions: [CoachAction]) -> String? {
        let added = actions.filter { $0.actionType == .inventory && $0.action == "add" }.compactMap { proseName($0.name) }
        let removed = actions.filter { $0.actionType == .inventory && $0.action == "remove" }.compactMap { proseName($0.name) }
        let budget = actions.first { $0.actionType == .budget }?.monthlyDollars
        var parts: [String] = []
        if !added.isEmpty {
            parts.append("Got it, I'll remember you have \(listed(added)), and I'll start with \(added.count == 1 ? "that" : "those") whenever \(added.count == 1 ? "it fits" : "they fit") before suggesting anything to buy.")
        }
        if !removed.isEmpty {
            parts.append("Noted that you're out of \(listed(removed)).")
        }
        if let dollars = budget {
            parts.append("I'll keep suggestions within about $\(Int(dollars.rounded())) a month.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Details

    struct Sentence {
        var text: String
        var isQuestion: Bool
    }

    /// Lowercased sentences, split at . ! ? ; and line breaks, and at "but".
    static func sentences(_ message: String) -> [Sentence] {
        var text = message.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "b.t.", with: "bt")
            .replacingOccurrences(of: "dr.", with: "dr")
        text = text.replacingOccurrences(of: ", but ", with: ". ").replacingOccurrences(of: " but ", with: ". ")
        var result: [Sentence] = []
        var current = ""
        for ch in text {
            if ".!?;\n".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(Sentence(text: " " + trimmed + " ", isQuestion: ch == "?")) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result.append(Sentence(text: " " + trimmed + " ", isQuestion: false)) }
        return result
    }

    /// Known supplies named in a sentence. The longest phrase wins where two overlap
    /// ("compost tea" is compost tea, not compost).
    static func supplies(in text: String) -> [Supply] {
        var hits: [(supply: Supply, range: Range<String.Index>)] = []
        for supply in supplies {
            for phrase in supply.phrases.sorted(by: { $0.count > $1.count }) {
                if let range = wholeWord(phrase, in: text) {
                    hits.append((supply, range))
                    break
                }
            }
        }
        var taken: [Range<String.Index>] = []
        var kept: [(supply: Supply, range: Range<String.Index>)] = []
        for hit in hits.sorted(by: { text.distance(from: $0.range.lowerBound, to: $0.range.upperBound) > text.distance(from: $1.range.lowerBound, to: $1.range.upperBound) }) {
            if taken.contains(where: { $0.overlaps(hit.range) }) { continue }
            taken.append(hit.range)
            kept.append(hit)
        }
        return kept.sorted { $0.range.lowerBound < $1.range.lowerBound }.map { $0.supply }
    }

    /// Finds `phrase` as whole words (a plural "s" after it is fine).
    static func wholeWord(_ phrase: String, in text: String) -> Range<String.Index>? {
        var start = text.startIndex
        while start < text.endIndex, let found = text.range(of: phrase, range: start..<text.endIndex) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            var end = found.upperBound
            if end < text.endIndex, text[end] == "s" { end = text.index(after: end) }
            let after = end == text.endIndex ? nil : text[end]
            let isWordChar: (Character?) -> Bool = { c in c.map { $0.isLetter || $0.isNumber } ?? false }
            if !isWordChar(before) && !isWordChar(after) { return found.lowerBound..<end }
            start = text.index(after: found.lowerBound)
        }
        return nil
    }

    /// "$30 a month", "my budget is 25 dollars", "$300 a year" (as a monthly figure).
    static func monthlyBudget(in text: String) -> Double? {
        let talksMoney = ["budget", "a month", "per month", "/month", "each month", "every month", "monthly", "to spend", "can spend"]
        guard talksMoney.contains(where: { text.contains($0) }) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"\$\s*(\d{1,5}(?:\.\d{1,2})?)|(\d{1,5}(?:\.\d{1,2})?)\s*(?:dollars|bucks)"#) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        guard group.location != NSNotFound, let value = Double(ns.substring(with: group)) else { return nil }
        if text.contains("year") || text.contains("annual") { return (value / 12).rounded() }
        if text.contains("a week") || text.contains("per week") || text.contains("weekly") { return (value * 52 / 12).rounded() }
        return value
    }

    static func proseName(_ name: String?) -> String? {
        guard let name = name else { return nil }
        return supplies.first { $0.name == name }?.prose ?? name
    }

    static func listed(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// Statements that mean they have it.
    static let positiveCues = [
        " i have ", " i've got ", " ive got ", " i got ", " i just got ", " we have ", " we've got ", " we got ",
        " i bought ", " we bought ", " i picked up ", " i ordered ", " i use ", " i used ", " we use ", " i make ", " we make ",
        " i keep ", " i collect ", " i save ", " gave me ", " i've been using ", " i own ", " i still have ", " there's a ",
        " i've also got ", " i also have ", " we also have ",
    ]
    /// In a question, only plain ownership counts ("Can I use the fish emulsion I have?").
    static let questionCues = [" i have ", " i've got ", " ive got ", " we have ", " we've got ", " i bought ", " i got ", " i still have "]
    /// Statements that mean it's gone.
    static let negativeCues = [
        " i'm out of ", " im out of ", " i am out of ", " we're out of ", " we are out of ", " all out of ", " fresh out of ",
        " ran out", " run out", " used up", " used the last", " don't have", " dont have", " do not have",
        " no longer have", " haven't got", " havent got", " have no ", " got rid of", " threw out",
    ]
    /// Phrases that look like a cue but aren't a statement about what they have.
    static let notStatements = [
        " have to ", " do i have", " do we have", " should i have", " i have been having", " i got to ",
        " have no idea", " have no clue",
    ]
    /// Hypotheticals and plans: say nothing.
    static let skips = [" if i ", " if we ", " what if ", " should i get ", " should i buy ", " thinking about getting ", " thinking of getting ", " want to get ", " want to buy ", " planning to "]
}
