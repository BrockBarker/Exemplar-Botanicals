import XCTest
@testable import GardenCore

final class SupplyMentionsTests: XCTestCase {
    private func added(_ message: String) -> [String] {
        SupplyMentions.actions(from: message).filter { $0.actionType == .inventory && $0.action == "add" }.compactMap { $0.name }
    }

    private func removed(_ message: String) -> [String] {
        SupplyMentions.actions(from: message).filter { $0.actionType == .inventory && $0.action == "remove" }.compactMap { $0.name }
    }

    func testPicksUpWhatTheyHave() {
        XCTAssertEqual(added("I've got a bag of alfalfa pellets and a compost pile."), ["Alfalfa pellets", "Compost"])
        XCTAssertEqual(added("My neighbor gave me a bunch of coffee grounds"), ["Coffee grounds"])
        XCTAssertEqual(added("I bought some Garden-tone yesterday"), ["Garden-tone"])
        XCTAssertEqual(added("We have a rain barrel and some straw."), ["Rain barrel", "Straw"])
        let action = SupplyMentions.actions(from: "I have neem oil").first
        XCTAssertEqual(action?.category, InventoryCategory.pestControl.rawValue)
        XCTAssertEqual(action?.displaySummary, "Remembered you have neem oil")
    }

    func testLongestNameWins() {
        XCTAssertEqual(added("I make compost tea every week"), ["Compost tea"])
        XCTAssertEqual(added("I have kelp meal"), ["Kelp meal"])
        XCTAssertEqual(added("I've got Alaska fish fertilizer"), ["Alaska fish fertilizer"])
    }

    func testWholeWordsOnly() {
        XCTAssertEqual(added("I have strawberries and yellow leaves"), [])
        XCTAssertEqual(added("I have a lime tree"), [])
        XCTAssertEqual(added("I have two rain barrels"), ["Rain barrel"])
    }

    func testRunningOut() {
        XCTAssertEqual(removed("I ran out of fish emulsion"), ["Fish emulsion"])
        XCTAssertEqual(removed("We're out of neem."), ["Neem oil"])
        // Each clause on its own: one added, one gone.
        let mixed = SupplyMentions.actions(from: "I still have compost but I used up the blood meal")
        XCTAssertEqual(mixed.map { $0.name ?? "" }, ["Compost", "Blood meal"])
        XCTAssertEqual(mixed.map { $0.action ?? "" }, ["add", "remove"])
    }

    func testIgnoresQuestionsPlansAndHypotheticals() {
        XCTAssertEqual(added("Should I use neem oil on aphids?"), [])
        XCTAssertEqual(added("How do I make compost tea?"), [])
        XCTAssertEqual(added("Do I have to use compost?"), [])
        XCTAssertEqual(added("If I have extra compost, where should it go?"), [])
        XCTAssertEqual(added("I'm thinking about getting blood meal"), [])
        XCTAssertEqual(SupplyMentions.actions(from: "I have no idea if compost is good").count, 0)
        XCTAssertEqual(added("I have aphids on my kale"), [])
        // A question can still say what they own.
        XCTAssertEqual(added("Can I use the fish emulsion I have on peppers?"), ["Fish emulsion"])
    }

    func testBudget() {
        let budget = SupplyMentions.actions(from: "My budget is about $30 a month.").first { $0.actionType == .budget }
        XCTAssertEqual(budget?.monthlyDollars, 30)
        let yearly = SupplyMentions.actions(from: "I can spend $240 a year on the garden").first { $0.actionType == .budget }
        XCTAssertEqual(yearly?.monthlyDollars, 20)
        XCTAssertTrue(SupplyMentions.actions(from: "Is $20 a month enough?").isEmpty)
        XCTAssertTrue(SupplyMentions.actions(from: "Alfalfa is $25 a bag").isEmpty)
    }

    func testDemoCoachConfirmsAndAnswersOnlyTheQuestion() {
        let profile = GardenProfileInfo()
        let message = "I've got a compost pile and neem oil. What should I do about aphids?"
        let noted = SupplyMentions.actions(from: message)
        let state = Fixtures.state(inventory: [
            InventoryInfo(name: "Compost", category: .compost), InventoryInfo(name: "Neem oil", category: .pestControl),
        ])
        let reply = DemoCoach.reply(to: message, state: state, profile: profile, now: Fixtures.morning, calendar: Fixtures.calendar, noted: noted)
        XCTAssertTrue(reply.hasPrefix("Got it, I'll remember you have compost and neem oil"))
        XCTAssertTrue(reply.contains("Neem oil"), "the pest answer should start with what they own")

        // Just telling, not asking: confirm and stop there (no feeding advice for a compost pile).
        let told = "I have a compost pile."
        let short = DemoCoach.reply(to: told, state: state, profile: profile, now: Fixtures.morning, calendar: Fixtures.calendar, noted: SupplyMentions.actions(from: told))
        XCTAssertEqual(short, "Got it, I'll remember you have compost, and I'll start with that whenever it fits before suggesting anything to buy.\n\n\(DemoCoach.notice)")
    }
}
