import XCTest
@testable import GardenCore

/// The offline coach follows David's own method (backend/persona/method.md).
final class DavidsMethodTests: XCTestCase {
    private func ask(_ question: String, _ state: GardenState = Fixtures.state()) -> String {
        DemoCoach.reply(to: question, state: state, profile: GardenProfileInfo(), now: Fixtures.morning, calendar: Fixtures.calendar)
    }

    func testRaisedBedMix() {
        let answer = ask("What should I fill my raised bed with?")
        XCTAssertTrue(answer.contains("half silty topsoil and half aged wood chips or finished compost"))
        XCTAssertTrue(answer.contains("up to about 10%"))
        XCTAssertTrue(answer.contains("None of the extras are entirely necessary"))

        let owned = Fixtures.state(inventory: [
            InventoryInfo(name: "Compost", category: .compost), InventoryInfo(name: "Biochar", category: .amendment),
            InventoryInfo(name: "Neem oil", category: .pestControl),
        ])
        XCTAssertTrue(ask("How do I build a raised bed?", owned).contains("you already have compost and biochar to work with"))
    }

    func testStartingAndTransplanting() {
        let start = ask("How do you start seeds for transplants?")
        XCTAssertTrue(start.contains("sifted compost with a bit of Azomite and MicroLife"))
        XCTAssertTrue(start.contains("liquid kelp and fish hydrolysate"))

        let out = ask("I'm about to transplant my collards. Anything I should do?")
        XCTAssertTrue(out.contains("mix a handful of MicroLife into the hole"))
        XCTAssertTrue(out.contains("2 or 3 weeks"))
        XCTAssertTrue(out.contains("Oak is my favorite"))
    }

    func testSiting() {
        let answer = ask("Where should I put my new bed?")
        XCTAssertTrue(answer.contains("face the bed south"))
        XCTAssertTrue(answer.contains("between where you park your car and where you walk into your house"))
        XCTAssertTrue(answer.contains("shade from the west in the afternoon"))
        XCTAssertTrue(ask("How do I build a raised bed?").contains("First, the spot"))
    }

    func testBedSize() {
        let answer = ask("How big should I make a raised bed?")
        XCTAssertTrue(answer.contains("5 feet wide, 2 feet tall and 10 to 12 feet long"))
        XCTAssertTrue(answer.contains("not dry out as fast"))
        XCTAssertTrue(ask("What should I fill my raised bed with?").contains("5 feet wide"))
    }

    func testWideSpacing() {
        XCTAssertTrue(ask("How far apart should I plant kale?").contains("exemplary individual"))
    }

    func testFoliarFeedAndMulchMentionHisPicks() {
        XCTAssertTrue(ask("How often should I foliar spray?").contains("liquid kelp and fish hydrolysate mixed in a small spray bottle"))
        let state = Fixtures.state(plants: [Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 40)])
        XCTAssertTrue(ask("What should I feed my tomatoes?", state).contains("MicroLife All Purpose"))
        XCTAssertTrue(ask("What mulch should I use?").contains("aged oak leaves"))
    }

    func testHisProductsLeadTheBuyTier() {
        let feed = Toolbox.ranked(for: .feed, inventory: [])
        XCTAssertEqual(feed.first { $0.tier == .branded }?.id, "microlife")
        XCTAssertEqual(feed.first?.id, "compost", "free options still come first")
        let foliar = Toolbox.ranked(for: .foliar, inventory: [])
        XCTAssertEqual(foliar.first { $0.tier == .branded }?.id, "kelp_fish")

        let owned = Toolbox.ranked(for: .feed, inventory: [InventoryInfo(name: "MicroLife All Purpose", category: .fertilizer)])
        XCTAssertEqual(owned.first?.tier, .owned)
        XCTAssertTrue(owned.first?.howTo.contains("handful into each planting hole") == true)
        XCTAssertFalse(owned.contains { $0.id == "microlife" })
    }

    func testWateringEggshellsAndNoConcentrates() {
        XCTAssertTrue(ask("How often should I water?").contains("never wilt"))
        XCTAssertTrue(ask("My new leaves are yellow between the veins").contains("never needed one for my own beds"))

        let feed = Toolbox.ranked(for: .feed, inventory: [
            InventoryInfo(name: "Blood meal", category: .fertilizer), InventoryInfo(name: "Rock phosphate", category: .amendment),
        ])
        XCTAssertFalse(feed.contains { $0.name.lowercased().contains("blood meal") || $0.name.lowercased().contains("rock phosphate") })
        XCTAssertFalse(feed.contains { $0.id == "blood_meal" || $0.id == "feather_meal" })
    }

    func testFoliarTimingAndHarvestGap() {
        let answer = ask("When should I foliar spray?")
        XCTAssertTrue(answer.contains("before the dew dries"))
        XCTAssertTrue(answer.contains("stomata"))
        XCTAssertTrue(answer.contains("within a couple of weeks of harvest"))
    }

    func testFeedUntilALittleTooGreenAndNoSalts() {
        XCTAssertTrue(ask("How much should I fertilize my peppers?").contains("a little too green, then stop"))
        XCTAssertTrue(ask("Should I use calcium nitrate for blossom end rot?").contains("I avoid salt fertilizers like calcium nitrate"))
        let feed = Toolbox.ranked(for: .feed, inventory: [InventoryInfo(name: "Calcium nitrate", category: .fertilizer)])
        XCTAssertFalse(feed.contains { $0.name == "Calcium nitrate" })

        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 60)
        let nudge = NudgeEngine(calendar: Fixtures.calendar).candidates(Fixtures.state(plants: [tomato]), now: Fixtures.morning)
            .first { $0.kind == .feed }
        XCTAssertTrue(nudge?.body.contains("Skip it if the leaves already look a little too green.") == true)
        XCTAssertTrue(nudge?.detail.contains("a little too green") == true)
    }

    func testKeepsItSimple() {
        let kit = ask("What products should I buy to get started?")
        XCTAssertTrue(kit.contains("Azomite, a quality brand of fish hydrolysate, a quality brand of kelp extract, and a good organic granular"))
        XCTAssertTrue(kit.contains("crushed oyster shells"))
        XCTAssertTrue(ask("Is compost tea worth making?").contains("more effort than result"))
        XCTAssertTrue(ask("What about Korean Natural Farming?").contains("more effort than results"))
        XCTAssertTrue(ask("Can I use chicken manure?").contains("I avoid chicken litter because of the arsenic"))

        let feed = Toolbox.ranked(for: .feed, inventory: [InventoryInfo(name: "Chicken manure", category: .compost)])
        XCTAssertFalse(feed.contains { $0.tier == .owned })
        XCTAssertTrue(feed.contains { $0.id == "manure" })
        let owned = Fixtures.state(inventory: [
            InventoryInfo(name: "Chicken manure", category: .compost), InventoryInfo(name: "Crushed oyster shells", category: .amendment),
        ])
        let mix = ask("How do I build a raised bed?", owned)
        XCTAssertTrue(mix.contains("you already have crushed oyster shells to work with"))
        XCTAssertFalse(mix.contains("you already have chicken"))
    }

    func testConsistencyAndRootBoundTransplants() {
        let answer = ask("The tomato transplants I bought are root bound. What do I do?")
        XCTAssertTrue(answer.contains("tease the roots out gently"))
        XCTAssertTrue(answer.contains("root-to-shoot ratio"))
        XCTAssertTrue(ask("How do you start seeds for transplants?").contains("Don't let them get root bound"))
    }

    func testRemembersHisMaterials() {
        let names = SupplyMentions.actions(from: "I've got MicroLife, some biochar and a bag of fish hydrolysate").compactMap { $0.name }
        XCTAssertEqual(names, ["MicroLife All Purpose", "Biochar", "Fish hydrolysate"])
        XCTAssertEqual(SupplyMentions.actions(from: "I have MicroLife").first?.displaySummary, "Remembered you have MicroLife All Purpose")
    }
}
