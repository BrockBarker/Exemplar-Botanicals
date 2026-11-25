import XCTest
@testable import GardenCore

/// David's care for new plantings: a daily water check and a weekly kelp and fish spray for the
/// first 3 weeks, sprayed early in the morning before the dew dries and never close to harvest.
final class NewPlantNudgeTests: XCTestCase {
    let engine = Fixtures.engine

    private func waterChecks(_ state: GardenState, now: Date = Fixtures.morning) -> [Nudge] {
        engine.candidates(state, now: now).filter { $0.dedupeKey.hasPrefix("new_plant_water_") }
    }

    private func spray(_ state: GardenState, now: Date = Fixtures.morning) -> Nudge? {
        engine.candidates(state, now: now).first { $0.dedupeKey == "new_plant_spray" }
    }

    private func key(_ offset: Int) -> String { "new_plant_water_\(Fixtures.day(offset).string)" }

    // MARK: Water

    func testDailyWaterChecksForTheFirstThreeWeeks() throws {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 3)
        let checks = waterChecks(Fixtures.state(beds: [bed], plants: [tomato]))
        XCTAssertEqual(checks.map { $0.dedupeKey }, (0..<7).map(key), "one a day for the coming week")
        let first = try XCTUnwrap(checks.first)
        XCTAssertEqual(first.kind, .moistureCheck)
        XCTAssertEqual(first.title, "Water check: new plants in Back bed")
        XCTAssertEqual(first.fireDate, Fixtures.at(0, 7, 30))
        XCTAssertEqual(first.bedIDs, [bed.id])
        XCTAssertTrue(first.body.contains("never wilt"))
        XCTAssertTrue(first.detail.contains("nearly every day"))
        XCTAssertEqual(first.log?.kind, .moistureCheck)

        // Planted 19 days ago: today and the next two days, then the checks stop.
        let older = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 19)
        XCTAssertEqual(waterChecks(Fixtures.state(beds: [bed], plants: [older])).map { $0.dedupeKey }, (0...2).map(key))
        let established = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 30)
        XCTAssertTrue(waterChecks(Fixtures.state(beds: [bed], plants: [established])).isEmpty)
    }

    func testSkipsTodayOnceWateredOrChecked() {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 3)
        let watered = JournalInfo(day: Fixtures.today, kind: .watering, what: "Watered", bedID: bed.id, waterInches: 0.5)
        XCTAssertEqual(waterChecks(Fixtures.state(beds: [bed], plants: [tomato], journal: [watered])).first?.dedupeKey, key(1))
        let checked = JournalInfo(day: Fixtures.today, kind: .moistureCheck, what: "Finger test", plantID: tomato.id, moisture: .moist)
        XCTAssertEqual(waterChecks(Fixtures.state(beds: [bed], plants: [tomato], journal: [checked])).first?.dedupeKey, key(1))
    }

    func testPlantsOutsideABed() throws {
        let pot = Fixtures.plant("Sungold", crop: "cherry_tomato", plantedDaysAgo: 2)
        let first = try XCTUnwrap(waterChecks(Fixtures.state(plants: [pot])).first)
        XCTAssertEqual(first.title, "Water check: the new Sungold")
        XCTAssertEqual(first.plantIDs, [pot.id])
        XCTAssertTrue(first.bedIDs.isEmpty)
    }

    func testSoakingRainSkipsThatDayAndTheNext() {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 3)
        let weather = Fixtures.weather { offset, d in
            if offset == 1 {
                d.rainInches = 0.8
                d.rainChance = 90
            }
        }
        let keys = waterChecks(Fixtures.state(beds: [bed], plants: [tomato], weather: weather)).map { $0.dedupeKey }
        XCTAssertFalse(keys.contains(key(1)))
        XCTAssertFalse(keys.contains(key(2)))
        XCTAssertTrue(keys.contains(key(4)))
    }

    func testRegularMoistureNudgesTakePriority() {
        let bed = Fixtures.bed()
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 3)
        let waterNow = Nudge(
            kind: .waterNow, dedupeKey: "water_now", cooldownDays: 1, priority: 80, fireDate: Fixtures.at(0, 7, 30),
            title: "Back bed is probably dry", body: "Water it.", bedIDs: [bed.id]
        )
        let checks = engine.newPlantWater(Fixtures.state(beds: [bed], plants: [tomato]), today: Fixtures.today, covered: [waterNow])
        XCTAssertEqual(checks.first?.dedupeKey, key(1))
    }

    // MARK: Weekly spray

    func testWeeklySprayForThreeWeeksAfterTransplanting() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 3)
        let nudge = try XCTUnwrap(spray(Fixtures.state(plants: [tomato])))
        XCTAssertEqual(nudge.kind, .foliar)
        XCTAssertEqual(nudge.title, "Kelp and fish spray for the new Big Beef")
        XCTAssertEqual(nudge.fireDate, Fixtures.at(4, 7, 30), "a week after planting")
        XCTAssertTrue(nudge.body.hasPrefix("Early in the morning, before the dew dries, mist the leaves"))
        XCTAssertTrue(nudge.body.contains("liquid kelp and fish hydrolysate"))
        XCTAssertTrue(nudge.detail.contains("stomata"))
        XCTAssertEqual(nudge.log?.kind, .foliarSpray)
        XCTAssertEqual(nudge.plantIDs, [tomato.id])

        // Sprayed 2 days ago: the next one is a week after that.
        let tenDays = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 10)
        let sprayed = JournalInfo(day: Fixtures.day(-2), kind: .foliarSpray, what: "Kelp and fish", plantID: tenDays.id)
        XCTAssertEqual(spray(Fixtures.state(plants: [tenDays], journal: [sprayed]))?.fireDate, Fixtures.at(5, 7, 30))

        // Never sprayed and 12 days in: due now.
        let overdue = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 12)
        XCTAssertEqual(spray(Fixtures.state(plants: [overdue]))?.fireDate, Fixtures.at(0, 7, 30))

        // The next spray would land past 3 weeks, so they're done.
        let late = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 18)
        let lateSpray = JournalInfo(day: Fixtures.day(-2), kind: .foliarSpray, what: "Kelp and fish", plantID: late.id)
        XCTAssertNil(spray(Fixtures.state(plants: [late], journal: [lateSpray])))
    }

    func testSprayPicksAnEarlyMorningWindow() throws {
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 7)
        let nudge = try XCTUnwrap(spray(Fixtures.state(plants: [tomato], weather: Fixtures.weather(hours: Fixtures.hours()))))
        // It's 6 AM, so this morning's window has started; tomorrow morning is next. Remind the evening before.
        XCTAssertEqual(nudge.fireDate, Fixtures.at(0, 18, 30))
        XCTAssertEqual(nudge.expires, Fixtures.at(1, 9))
        XCTAssertTrue(nudge.body.hasPrefix("Tomorrow 6–9 AM looks calm and cool. Before the dew dries, mist the leaves"))
    }

    func testNoSprayWithinTwoWeeksOfHarvest() {
        // Radishes are ready in about 25 days, so at 12 days they're too close.
        let radish = Fixtures.plant("French Breakfast", crop: "radish", plantedDaysAgo: 12)
        XCTAssertNil(spray(Fixtures.state(plants: [radish])))
        let early = Fixtures.plant("French Breakfast", crop: "radish", plantedDaysAgo: 8)
        XCTAssertNotNil(spray(Fixtures.state(plants: [early])))
    }

    func testRegularFoliarLeavesNewAndNearlyReadyPlantsAlone() {
        let hours = Fixtures.weather(hours: Fixtures.hours())
        let general: (GardenState) -> [Nudge] = { state in
            self.engine.candidates(state, now: Fixtures.morning).filter { $0.dedupeKey == "foliar" }
        }
        let young = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 18)
        XCTAssertTrue(general(Fixtures.state(plants: [young], weather: hours)).isEmpty, "the weekly transplant spray covers it")
        let fruiting = Fixtures.plant("Big Beef", crop: "tomato", plantedDaysAgo: 60, stage: .fruiting)
        XCTAssertTrue(general(Fixtures.state(plants: [fruiting], weather: hours)).isEmpty, "already picking")
        let rose = Fixtures.plant("Peace", crop: "rose", plantedDaysAgo: 400)
        XCTAssertFalse(general(Fixtures.state(plants: [rose], weather: hours)).isEmpty)
        let cut = JournalInfo(day: Fixtures.day(-3), kind: .harvest, what: "A few blooms", plantID: rose.id)
        XCTAssertTrue(general(Fixtures.state(plants: [rose], journal: [cut], weather: hours)).isEmpty, "picked within 2 weeks")
    }
}
