import XCTest
@testable import GardenCore

/// Harvest, pest checks, pruning, succession sowing and the season wrap-up.
final class NudgeCareTests: XCTestCase {
    let engine = Fixtures.engine

    private func candidates(_ state: GardenState, kind: NudgeKind) -> [Nudge] {
        engine.candidates(state, now: Fixtures.morning).filter { $0.kind == kind }
    }

    // MARK: Harvest

    func testFruitingPickersGetAHarvestCheck() throws {
        let sungold = Fixtures.plant("Sungold", crop: "cherry_tomato", plantedDaysAgo: 70, stage: .fruiting)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [sungold]), kind: .harvest).first)
        XCTAssertEqual(nudge.dedupeKey, "harvest")
        XCTAssertEqual(nudge.title, "Harvest check: Sungold")
        XCTAssertTrue(nudge.body.contains("fully colored"))
        XCTAssertEqual(nudge.log?.kind, .harvest)
        XCTAssertEqual(nudge.priority, 60)

        let picked = JournalInfo(day: Fixtures.day(-1), kind: .harvest, what: "A pint", plantID: sungold.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [sungold], journal: [picked]), kind: .harvest).isEmpty)
        let pickedEarlier = JournalInfo(day: Fixtures.day(-3), kind: .harvest, what: "A pint", plantID: sungold.id)
        XCTAssertFalse(candidates(Fixtures.state(plants: [sungold], journal: [pickedEarlier]), kind: .harvest).isEmpty)
    }

    func testHarvestComingSoonFromThePlantingDate() throws {
        let carrots = Fixtures.plant("Nantes", crop: "carrot", plantedDaysAgo: 65)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [carrots]), kind: .harvest).first)
        XCTAssertEqual(nudge.dedupeKey, "harvest_soon")
        XCTAssertEqual(nudge.title, "Harvest coming: Nantes")
        XCTAssertTrue(nudge.body.contains("about 5 days"))
        XCTAssertNil(nudge.log)
    }

    func testOneTimeHarvestsStopOnceLoggedOrLongPast() {
        let carrots = Fixtures.plant("Nantes", crop: "carrot", plantedDaysAgo: 75)
        XCTAssertEqual(candidates(Fixtures.state(plants: [carrots]), kind: .harvest).first?.dedupeKey, "harvest")
        let dug = JournalInfo(day: Fixtures.day(-2), kind: .harvest, what: "Pulled them all", plantID: carrots.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [carrots], journal: [dug]), kind: .harvest).isEmpty)
        let forgotten = Fixtures.plant("Nantes", crop: "carrot", plantedDaysAgo: 130)
        XCTAssertTrue(candidates(Fixtures.state(plants: [forgotten]), kind: .harvest).isEmpty)
    }

    func testSeedlingsAreNotHarvested() {
        let late = Fixtures.plant("Nantes", crop: "carrot", plantedDaysAgo: 80, stage: .seedling)
        XCTAssertTrue(candidates(Fixtures.state(plants: [late]), kind: .harvest).isEmpty)
    }

    // MARK: Pest checks

    func testWeeklyPestCheckInWarmWeather() throws {
        let zucchini = Fixtures.plant("Costata", crop: "summer_squash", plantedDaysAgo: 40)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [zucchini], weather: Fixtures.weather()), kind: .pestCheck).first)
        XCTAssertTrue(nudge.body.contains("squash bugs"))
        XCTAssertTrue(nudge.detail.contains("Pick them off"))
        XCTAssertEqual(nudge.cooldownDays, 7)

        let checked = JournalInfo(day: Fixtures.day(-3), kind: .pestOrDisease, what: "Squished eggs", plantID: zucchini.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [zucchini], journal: [checked], weather: Fixtures.weather()), kind: .pestCheck).isEmpty)
        XCTAssertTrue(candidates(Fixtures.state(plants: [zucchini], weather: Fixtures.weather(high: 55)), kind: .pestCheck).isEmpty)
        XCTAssertTrue(candidates(Fixtures.state(plants: [zucchini]), kind: .pestCheck).isEmpty, "needs weather")
    }

    // MARK: Pruning

    func testPruningForCropsThatNeedIt() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 30)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato]), kind: .pruning).first)
        XCTAssertTrue(nudge.body.hasPrefix("Big Beef: Pinch out suckers"))
        XCTAssertEqual(nudge.log?.kind, .pruning)

        let pruned = JournalInfo(day: Fixtures.day(-5), kind: .pruning, what: "Suckers", plantID: tomato.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [tomato], journal: [pruned]), kind: .pruning).isEmpty)
        let young = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 10)
        XCTAssertTrue(candidates(Fixtures.state(plants: [young]), kind: .pruning).isEmpty)
        let pepper = Fixtures.plant("Jalapeño", crop: "pepper", plantedDaysAgo: 30)
        XCTAssertTrue(candidates(Fixtures.state(plants: [pepper]), kind: .pruning).isEmpty)
    }

    // MARK: Succession

    func testSowAgainForQuickCrops() throws {
        let lettuce = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 20)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [lettuce], weather: Fixtures.weather()), kind: .succession).first)
        XCTAssertEqual(nudge.title, "Time to sow more lettuce")
        XCTAssertTrue(nudge.body.hasPrefix("It's been 20 days since the last lettuce went in."))
        XCTAssertEqual(nudge.log?.kind, .planting)

        let recent = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 10)
        XCTAssertTrue(candidates(Fixtures.state(plants: [recent], weather: Fixtures.weather()), kind: .succession).isEmpty)
        let longAgo = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 50)
        XCTAssertTrue(candidates(Fixtures.state(plants: [longAgo], weather: Fixtures.weather()), kind: .succession).isEmpty)
        let sowed = JournalInfo(day: Fixtures.day(-5), kind: .planting, what: "Another row", plantID: lettuce.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [lettuce], journal: [sowed], weather: Fixtures.weather()), kind: .succession).isEmpty)
    }

    func testNoSowingIntoHeatOrPastTheSeason() {
        let lettuce = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 20)
        XCTAssertTrue(candidates(Fixtures.state(plants: [lettuce], weather: Fixtures.weather(high: 91)), kind: .succession).isEmpty)

        let shortSeason = GardenState(
            beds: [], plants: [lettuce], journal: [], inventory: [], weather: Fixtures.weather(), firstFallFrost: Fixtures.day(20)
        )
        XCTAssertTrue(candidates(shortSeason, kind: .succession).isEmpty, "45 days to harvest won't fit")
    }

    // MARK: Season end

    func testSeasonWrapUpBeforeTheFirstFrost() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 90, stage: .fruiting)
        let state = GardenState(beds: [], plants: [tomato], journal: [], inventory: [], weather: nil, firstFallFrost: Fixtures.day(14))
        let nudge = try XCTUnwrap(candidates(state, kind: .seasonEnd).first)
        XCTAssertEqual(nudge.dedupeKey, "season_end:2026")
        XCTAssertEqual(nudge.cooldownDays, 0)
        XCTAssertTrue(nudge.title.hasPrefix("First frost around"))
        XCTAssertTrue(nudge.body.hasPrefix("Pick everything ripe or close to it on the Big Beef"))
        XCTAssertTrue(nudge.detail.contains("Plant garlic"))

        let farOff = GardenState(beds: [], plants: [tomato], journal: [], inventory: [], weather: nil, firstFallFrost: Fixtures.day(40))
        XCTAssertTrue(candidates(farOff, kind: .seasonEnd).isEmpty)
        // A cold night in July is a frost warning, not the end of the season.
        let cold = Fixtures.weather { offset, d in if offset == 3 { d.lowF = 33 } }
        XCTAssertTrue(candidates(Fixtures.state(plants: [tomato], weather: cold), kind: .seasonEnd).isEmpty)
    }

    // MARK: Demo coach

    private func ask(_ question: String, _ state: GardenState, profile: GardenProfileInfo = GardenProfileInfo()) -> String {
        DemoCoach.reply(to: question, state: state, profile: profile, now: Fixtures.morning, calendar: Fixtures.calendar)
    }

    func testDemoCoachOverviewCoversTheWholeGarden() {
        let sungold = Fixtures.plant("Sungold", crop: "cherry_tomato", plantedDaysAgo: 70, stage: .fruiting)
        let answer = ask("What should I be doing this week?", Fixtures.state(plants: [sungold], weather: Fixtures.weather()))
        XCTAssertTrue(answer.hasPrefix("Here's what I'd do this week:"))
        XCTAssertTrue(answer.contains("Harvest check: Sungold"))
        XCTAssertFalse(answer.lowercased().contains("urine"))
        XCTAssertTrue(ask("Hi", Fixtures.state()).hasPrefix("Add your beds and plants"))
    }

    func testDemoCoachHarvestTiming() {
        let carrots = Fixtures.plant("Nantes", crop: "carrot", plantedDaysAgo: 60)
        let answer = ask("What's ready to harvest?", Fixtures.state(plants: [carrots]))
        XCTAssertTrue(answer.contains("Nantes: about 10 days to go (usually around day 70)."))
    }

    func testDemoCoachDoesNotJumpToFeedingOrUrine() {
        let state = Fixtures.state(plants: [Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 40)])
        let yellow = ask("My lower leaves are turning yellow", state)
        XCTAssertTrue(yellow.contains("feeding isn't always the fix"))
        XCTAssertFalse(yellow.lowercased().contains("urine"))
        XCTAssertFalse(ask("What should I feed my tomatoes?", state).lowercased().contains("urine"))

        XCTAssertTrue(ask("Can I use urine on them?", state).contains("1 part to 10 parts water"))
        XCTAssertTrue(ask("Can I use urine on them?", state, profile: GardenProfileInfo(avoidUrine: true)).contains("leave urine out"))
    }

    func testDemoCoachPestsAndPruning() {
        let state = Fixtures.state(plants: [Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 40)])
        let pests = ask("Something is eating my tomatoes", state)
        XCTAssertTrue(pests.contains("hornworms"))
        XCTAssertTrue(pests.contains("1. Pick them off"))
        XCTAssertTrue(ask("Should I prune?", state).contains("Pinch out suckers"))
    }
}
