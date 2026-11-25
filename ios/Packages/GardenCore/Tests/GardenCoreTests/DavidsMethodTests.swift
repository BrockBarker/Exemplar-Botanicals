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

    func testRemembersHisMaterials() {
        let names = SupplyMentions.actions(from: "I've got MicroLife, some biochar and a bag of fish hydrolysate").compactMap { $0.name }
        XCTAssertEqual(names, ["MicroLife All Purpose", "Biochar", "Fish hydrolysate"])
        XCTAssertEqual(SupplyMentions.actions(from: "I have MicroLife").first?.displaySummary, "Remembered you have MicroLife All Purpose")
    }
}
