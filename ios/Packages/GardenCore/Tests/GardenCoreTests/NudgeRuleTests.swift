import XCTest
@testable import GardenCore

/// One test group per nudge rule. Each checks the rule fires when it should, stays quiet when
/// it shouldn't, and that the wording carries the facts.
final class NudgeRuleTests: XCTestCase {
    let engine = Fixtures.engine

    private func candidates(_ state: GardenState, now: Date = Fixtures.morning, kind: NudgeKind) -> [Nudge] {
        engine.candidates(state, now: now).filter { $0.kind == kind }
    }

    // MARK: Frost

    func testFrostWarnsTheAfternoonBefore() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato")
        let weather = Fixtures.weather { offset, d in if offset == 1 { d.lowF = 31 } }
        let frost = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], weather: weather), kind: .frost).first)
        XCTAssertEqual(frost.dedupeKey, "frost:2026-07-15")
        XCTAssertEqual(frost.cooldownDays, 0)
        XCTAssertEqual(frost.fireDate, Fixtures.at(0, 16))
        XCTAssertEqual(frost.expires, Fixtures.at(0, 22))
        XCTAssertEqual(frost.title, "Frost likely tonight (31°F)")
        XCTAssertTrue(frost.body.contains("Big Beef"))
        XCTAssertTrue(frost.detail.contains("Old sheets or blankets"))
        XCTAssertEqual(frost.plantIDs, [tomato.id])
    }

    func testFrostIgnoresHardyPlantsAndMildNights() {
        let kale = Fixtures.plant("Lacinato", crop: "kale")
        let cold = Fixtures.weather { offset, d in if offset == 1 { d.lowF = 31 } }
        XCTAssertTrue(candidates(Fixtures.state(plants: [kale], weather: cold), kind: .frost).isEmpty)
        let tomato = Fixtures.plant("Big Beef", crop: "tomato")
        XCTAssertTrue(candidates(Fixtures.state(plants: [tomato], weather: Fixtures.weather(low: 40)), kind: .frost).isEmpty)
    }

    // MARK: Heat and dry spells

    func testHeatWave() throws {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed)
        let weather = Fixtures.weather { offset, d in
            if offset == 1 { d.highF = 94 }
            if offset == 2 { d.highF = 97 }
        }
        let state = Fixtures.state(beds: [bed], plants: [tomato], weather: weather)
        let heat = try XCTUnwrap(candidates(state, kind: .heatStress).first)
        XCTAssertEqual(heat.title, "Heat wave from tomorrow: up to 97°F")
        XCTAssertEqual(heat.fireDate, Fixtures.at(0, 7, 30))
        XCTAssertEqual(heat.expires, Fixtures.at(1, 12))
        XCTAssertTrue(heat.body.contains("Back bed"))
        XCTAssertEqual(heat.log?.kind, .watering)
        // A heat warning replaces the dry-spell nudge.
        XCTAssertTrue(candidates(state, kind: .drySpell).isEmpty)
    }

    func testHotAfternoonDoesNotWarnAboutToday() {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed)
        let weather = Fixtures.weather { offset, d in if offset == 0 { d.highF = 95 } }
        let state = Fixtures.state(beds: [bed], plants: [tomato], weather: weather)
        XCTAssertEqual(candidates(state, now: Fixtures.morning, kind: .heatStress).first?.title, "Hot today: 95°F")
        XCTAssertTrue(candidates(state, now: Fixtures.at(0, 14), kind: .heatStress).isEmpty)
    }

    func testDrySpell() throws {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed)
        let dry = Fixtures.state(beds: [bed], plants: [tomato], weather: Fixtures.weather(rain: 0, et0: 0.2))
        let nudge = try XCTUnwrap(candidates(dry, kind: .drySpell).first)
        XCTAssertEqual(nudge.title, "Dry spell: 0 in of rain this week")
        XCTAssertTrue(nudge.detail.contains("1.4 in"))

        let rained = Fixtures.weather(rain: 0, et0: 0.2) { offset, d in if offset == -2 { d.rainInches = 0.6 } }
        XCTAssertTrue(candidates(Fixtures.state(beds: [bed], plants: [tomato], weather: rained), kind: .drySpell).isEmpty)
        let rainAhead = Fixtures.weather(rain: 0, et0: 0.2) { offset, d in if offset == 2 { d.rainInches = 0.5 } }
        XCTAssertTrue(candidates(Fixtures.state(beds: [bed], plants: [tomato], weather: rainAhead), kind: .drySpell).isEmpty)
    }

    // MARK: Soil moisture

    func testWaterNowWhenTheBedIsLikelyDry() throws {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 60, stage: .fruiting)
        let state = Fixtures.state(beds: [bed], plants: [tomato], weather: Fixtures.weather(et0: 0.25))
        let nudge = try XCTUnwrap(candidates(state, kind: .waterNow).first)
        XCTAssertEqual(nudge.title, "Back bed is probably dry")
        XCTAssertEqual(nudge.fireDate, Fixtures.at(0, 7, 30))
        XCTAssertEqual(nudge.bedIDs, [bed.id])
        XCTAssertEqual(nudge.log?.waterInches, WaterAmount.deep)
    }

    func testNoWaterNudgeAfterWateringToday() {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 60, stage: .fruiting)
        let watered = JournalInfo(day: Fixtures.today, kind: .watering, what: "Deep soak", bedID: bed.id, waterInches: 1)
        let state = Fixtures.state(beds: [bed], plants: [tomato], journal: [watered], weather: Fixtures.weather(et0: 0.25))
        XCTAssertTrue(candidates(state, kind: .waterNow).isEmpty)
        XCTAssertTrue(candidates(state, kind: .moistureCheck).isEmpty)
    }

    func testWaterNudgeLooksAhead() throws {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 60, stage: .fruiting)
        let check = JournalInfo(day: Fixtures.day(-1), kind: .moistureCheck, what: "Finger test", bedID: bed.id, moisture: .moist)
        let state = Fixtures.state(beds: [bed], plants: [tomato], journal: [check], weather: Fixtures.weather(et0: 0.25))
        // Moist yesterday; at about 0.32 in a day it's likely dry by tomorrow.
        let nudge = try XCTUnwrap(candidates(state, kind: .waterNow).first)
        XCTAssertEqual(nudge.fireDate, Fixtures.at(1, 7, 30))
    }

    func testEmptyBedsGetNoMoistureNudges() {
        let bed = Fixtures.bed()
        let state = Fixtures.state(beds: [bed], weather: Fixtures.weather(et0: 0.25))
        XCTAssertTrue(candidates(state, kind: .waterNow).isEmpty)
        XCTAssertTrue(candidates(state, kind: .drySpell).isEmpty)
    }

    // MARK: Wind and staking

    func testWindWarnsTheDayBefore() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", stage: .flowering)
        let weather = Fixtures.weather { offset, d in if offset == 1 { d.gustMaxMph = 32 } }
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], weather: weather), kind: .wind).first)
        XCTAssertEqual(nudge.title, "Windy tomorrow: gusts near 32 mph")
        XCTAssertEqual(nudge.fireDate, Fixtures.at(0, 7, 30))
        XCTAssertEqual(nudge.expires, Fixtures.at(1, 12))
    }

    func testStakingAfterTheCropsWindow() throws {
        let young = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 5)
        let due = Fixtures.plant("Sungold", crop: "cherry_tomato", plantedDaysAgo: 12)
        let staked = Fixtures.plant("Early Girl", crop: "tomato", plantedDaysAgo: 30, staked: true)
        let lettuce = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 30)
        let state = Fixtures.state(plants: [young, due, staked, lettuce])
        let nudge = try XCTUnwrap(candidates(state, kind: .staking).first)
        XCTAssertEqual(nudge.plantIDs, [due.id])
        XCTAssertEqual(nudge.title, "Time to stake the Sungold")
        XCTAssertTrue(nudge.body.hasPrefix("They've been in 12 days without support."))
    }

    // MARK: Foliar

    func testFoliarFindsTheNextCalmCoolWindow() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 30)
        let state = Fixtures.state(plants: [tomato], weather: Fixtures.weather(hours: Fixtures.hours()))
        let nudge = try XCTUnwrap(candidates(state, kind: .foliar).first)
        // It's 6 AM, so this morning's window has started; the evening one is next.
        XCTAssertEqual(nudge.title, "Foliar window today 6–8 PM")
        XCTAssertEqual(nudge.fireDate, Fixtures.at(0, 15))
        XCTAssertEqual(nudge.expires, Fixtures.at(0, 20))
        XCTAssertTrue(nudge.body.hasPrefix("70°F, calm and dry."))
        XCTAssertTrue(nudge.body.contains("compost tea"))
    }

    func testFoliarUsesWhatTheGardenerOwns() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 30)
        let kelp = InventoryInfo(name: "Maxicrop", category: .foliar)
        let state = Fixtures.state(plants: [tomato], inventory: [kelp], weather: Fixtures.weather(hours: Fixtures.hours()))
        XCTAssertTrue(try XCTUnwrap(candidates(state, kind: .foliar).first).body.contains("your Maxicrop"))
    }

    func testFoliarSkipsWindyHotOrRecentlySprayed() {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 30)
        let windy = Fixtures.state(plants: [tomato], weather: Fixtures.weather(hours: Fixtures.hours(wind: 14)))
        XCTAssertTrue(candidates(windy, kind: .foliar).isEmpty)
        let hot = Fixtures.state(plants: [tomato], weather: Fixtures.weather(hours: Fixtures.hours(temp: 92)))
        XCTAssertTrue(candidates(hot, kind: .foliar).isEmpty)
        let sprayed = JournalInfo(day: Fixtures.day(-5), kind: .foliarSpray, what: "Kelp", plantID: tomato.id)
        let recent = Fixtures.state(plants: [tomato], journal: [sprayed], weather: Fixtures.weather(hours: Fixtures.hours()))
        XCTAssertTrue(candidates(recent, kind: .foliar).isEmpty)
    }

    // MARK: Feeding

    func testFirstFeed() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 7)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], weather: Fixtures.weather()), kind: .firstFeed).first)
        XCTAssertEqual(nudge.title, "First feed for the Big Beef")
        XCTAssertTrue(nudge.body.contains("Use diluted urine"))
        XCTAssertEqual(nudge.fireDate, Fixtures.at(0, 7, 30))
    }

    func testRoutineFeedChecksTheJournal() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 60)
        let oldFeed = JournalInfo(day: Fixtures.day(-25), kind: .feeding, what: "Compost", plantName: "big beef")
        let due = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], journal: [oldFeed]), kind: .feed).first)
        XCTAssertEqual(due.dedupeKey, "feed")
        XCTAssertTrue(due.body.hasPrefix("Last feed was 25 days ago."))

        let recentFeed = JournalInfo(day: Fixtures.day(-5), kind: .feeding, what: "Compost", plantID: tomato.id)
        XCTAssertTrue(candidates(Fixtures.state(plants: [tomato], journal: [recentFeed]), kind: .feed).isEmpty)
    }

    func testSideDressAtFlowering() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 50, stage: .flowering)
        let fed = JournalInfo(day: Fixtures.day(-15), kind: .feeding, what: "Compost", plantID: tomato.id)
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], journal: [fed]), kind: .feed).first)
        XCTAssertEqual(nudge.dedupeKey, "side_dress")
    }

    func testLeafyCropsSkipUrineAndOwnedProductsComeFirst() throws {
        let lettuce = Fixtures.plant("Butterhead", crop: "lettuce", plantedDaysAgo: 60)
        let leafy = try XCTUnwrap(candidates(Fixtures.state(plants: [lettuce]), kind: .feed).first)
        XCTAssertTrue(leafy.body.contains("Use compost or worm castings"))
        XCTAssertFalse(leafy.detail.contains("Diluted urine ("))

        let fish = InventoryInfo(name: "Alaska Fish Fertilizer", category: .fertilizer)
        let owned = try XCTUnwrap(candidates(Fixtures.state(plants: [lettuce], inventory: [fish]), kind: .feed).first)
        XCTAssertTrue(owned.body.contains("Use your Alaska Fish Fertilizer"))
    }

    func testFeedingWaitsOutExtremeHeat() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 60)
        let weather = Fixtures.weather { offset, d in if offset == 0 || offset == 1 { d.highF = 97 } }
        let nudge = try XCTUnwrap(candidates(Fixtures.state(plants: [tomato], weather: weather), kind: .feed).first)
        XCTAssertEqual(nudge.fireDate, Fixtures.at(2, 7, 30))
        XCTAssertTrue(nudge.body.hasSuffix("Wait until the heat breaks."))
    }

    func testDisabledSettingsMeanNoNudges() {
        var settings = NudgeSettings.standard
        settings.enabled = false
        let engine = NudgeEngine(settings: settings, calendar: Fixtures.calendar)
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 12)
        XCTAssertTrue(engine.candidates(Fixtures.state(plants: [tomato]), now: Fixtures.morning).isEmpty)
    }

    func testText() {
        XCTAssertEqual(NudgeText.list(["A"]), "A")
        XCTAssertEqual(NudgeText.list(["A", "a", "B"]), "A and B")
        XCTAssertEqual(NudgeText.list(["A", "B", "C", "D", "E"]), "A, B and 3 more")
        XCTAssertEqual(NudgeText.temp(31.6), "32°F")
        XCTAssertEqual(NudgeText.inches(0.01), "0 in")
        XCTAssertEqual(NudgeText.inches(1.26), "1.3 in")
        XCTAssertEqual(NudgeText.hourRange(Fixtures.at(0, 6), Fixtures.at(0, 9), calendar: Fixtures.calendar), "6–9 AM")
        XCTAssertEqual(NudgeText.hourRange(Fixtures.at(0, 11), Fixtures.at(0, 13), calendar: Fixtures.calendar), "11 AM–1 PM")
    }
}
