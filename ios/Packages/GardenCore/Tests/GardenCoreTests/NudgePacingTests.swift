import XCTest
@testable import GardenCore

final class NudgePacingTests: XCTestCase {
    let engine = Fixtures.engine

    private func schedule(_ nudges: [Nudge], history: [NudgeHistory] = [], now: Date = Fixtures.morning) -> [Nudge] {
        engine.schedule(nudges, history: history, now: now)
    }

    func testQuietHoursMoveToMorning() {
        XCTAssertEqual(schedule([Fixtures.nudge("late", at: Fixtures.at(0, 22, 30))]).first?.fireDate, Fixtures.at(1, 7))
        XCTAssertEqual(schedule([Fixtures.nudge("early", at: Fixtures.at(1, 3))]).first?.fireDate, Fixtures.at(1, 7))
        XCTAssertEqual(schedule([Fixtures.nudge("day", at: Fixtures.at(1, 13))]).first?.fireDate, Fixtures.at(1, 13))
    }

    func testDailyCapKeepsTheMostImportant() {
        let result = schedule([
            Fixtures.nudge("a", priority: 90, at: Fixtures.at(1, 8)),
            Fixtures.nudge("b", priority: 50, at: Fixtures.at(1, 12)),
            Fixtures.nudge("c", priority: 70, at: Fixtures.at(1, 16)),
        ])
        XCTAssertEqual(result.map { $0.dedupeKey }, ["a", "c"])
    }

    func testSpacing() {
        let result = schedule([
            Fixtures.nudge("a", priority: 60, at: Fixtures.at(1, 8)),
            Fixtures.nudge("b", priority: 50, at: Fixtures.at(1, 8)),
        ])
        XCTAssertEqual(result.map { $0.fireDate }, [Fixtures.at(1, 8), Fixtures.at(1, 10)])
    }

    func testCooldown() {
        let history = [NudgeHistory(dedupeKey: "staking", date: Fixtures.at(-1, 7, 30))]
        let result = schedule([Fixtures.nudge("staking", at: Fixtures.at(0, 7, 30), cooldownDays: 4)], history: history)
        // Four days after the last one, an hour early is allowed, then out of quiet hours.
        XCTAssertEqual(result.first?.fireDate, Fixtures.at(3, 7))
    }

    func testOneTimeNudgesDontRepeat() {
        let history = [NudgeHistory(dedupeKey: "frost:2026-07-15", date: Fixtures.at(-1, 16))]
        let frost = Fixtures.nudge("frost:2026-07-15", kind: .frost, priority: 100, at: Fixtures.at(0, 16), cooldownDays: 0)
        XCTAssertTrue(schedule([frost], history: history).isEmpty)
    }

    func testSnoozeBringsItBack() {
        let frost = Fixtures.nudge(
            "frost:2026-07-15", kind: .frost, priority: 100, at: Fixtures.at(0, 16), cooldownDays: 0, expires: Fixtures.at(0, 22)
        )
        let history = [
            NudgeHistory(dedupeKey: "frost:2026-07-15", date: Fixtures.at(0, 16)),
            NudgeHistory(dedupeKey: "frost:2026-07-15", date: Fixtures.at(0, 16, 5), snoozedUntil: Fixtures.at(0, 18)),
        ]
        XCTAssertEqual(schedule([frost], history: history, now: Fixtures.at(0, 16, 5)).first?.fireDate, Fixtures.at(0, 18))
    }

    func testExpiredAndOutOfHorizonAreDropped() {
        let late = Fixtures.nudge("frost", kind: .frost, at: Fixtures.at(0, 21, 30), expires: Fixtures.at(0, 22))
        XCTAssertTrue(schedule([late]).isEmpty)
        XCTAssertTrue(schedule([Fixtures.nudge("far", at: Fixtures.at(9, 8))]).isEmpty)
    }

    func testPastTimesFireNow() {
        let now = Fixtures.at(0, 10)
        let result = schedule([Fixtures.nudge("water_now", at: Fixtures.at(0, 7, 30))], now: now)
        XCTAssertEqual(result.first?.fireDate, now.addingTimeInterval(60))
    }

    func testSameKeyOnlyOnce() {
        let result = schedule([
            Fixtures.nudge("feed", priority: 45, at: Fixtures.at(1, 8)),
            Fixtures.nudge("feed", priority: 55, at: Fixtures.at(2, 8)),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.priority, 55)
    }

    func testQuietHoursThatDontWrap() {
        var settings = NudgeSettings.standard
        settings.quietStartMinute = 12 * 60
        settings.quietEndMinute = 13 * 60
        XCTAssertTrue(settings.isQuiet(minute: 12 * 60 + 30))
        XCTAssertFalse(settings.isQuiet(minute: 22 * 60))
        let engine = NudgeEngine(settings: settings, calendar: Fixtures.calendar)
        XCTAssertEqual(engine.outOfQuietHours(Fixtures.at(1, 12, 15)), Fixtures.at(1, 13))
    }

    // MARK: Ledger

    /// A cherry tomato that needs staking and was fed recently, so staking is the only nudge.
    private func stakingState() -> GardenState {
        let plant = Fixtures.plant("Sungold", crop: "cherry_tomato", plantedDaysAgo: 12)
        let fed = JournalInfo(day: Fixtures.day(-5), kind: .feeding, what: "Compost", plantID: plant.id)
        return Fixtures.state(plants: [plant], journal: [fed])
    }

    func testLedgerDeliversAndRespectsCooldown() throws {
        var ledger = NudgeLedger()
        let plan = ledger.replan(engine: engine, state: stakingState(), now: Fixtures.morning)
        let staking = try XCTUnwrap(plan.first { $0.kind == .staking })
        XCTAssertEqual(staking.fireDate, Fixtures.at(0, 7, 30))
        XCTAssertTrue(ledger.inbox(now: Fixtures.morning).isEmpty)
        XCTAssertEqual(ledger.upcoming(now: Fixtures.morning).map { $0.id }, [staking.id])

        ledger.settle(now: Fixtures.at(0, 8))
        XCTAssertEqual(ledger.inbox(now: Fixtures.at(0, 8)).map { $0.id }, [staking.id])
        XCTAssertEqual(ledger.history.map { $0.dedupeKey }, ["staking"])
        XCTAssertNotNil(ledger.nudge(id: staking.id))

        ledger.markHandled(staking, now: Fixtures.at(0, 8))
        XCTAssertTrue(ledger.inbox(now: Fixtures.at(0, 8)).isEmpty)

        let next = ledger.replan(engine: engine, state: stakingState(), now: Fixtures.at(0, 9))
        XCTAssertEqual(next.first { $0.kind == .staking }?.fireDate, Fixtures.at(4, 7))
    }

    func testLedgerSnooze() throws {
        var ledger = NudgeLedger()
        ledger.replan(engine: engine, state: stakingState(), now: Fixtures.morning)
        ledger.settle(now: Fixtures.at(0, 8))
        let staking = try XCTUnwrap(ledger.inbox(now: Fixtures.at(0, 8)).first)
        ledger.snooze(staking, until: Fixtures.at(0, 12), now: Fixtures.at(0, 8))
        XCTAssertTrue(ledger.inbox(now: Fixtures.at(0, 8)).isEmpty)
        let next = ledger.replan(engine: engine, state: stakingState(), now: Fixtures.at(0, 9))
        XCTAssertEqual(next.first { $0.kind == .staking }?.fireDate, Fixtures.at(0, 12))
    }

    func testHandlingBeforeItFiresCancelsIt() throws {
        var ledger = NudgeLedger()
        let plan = ledger.replan(engine: engine, state: stakingState(), now: Fixtures.morning)
        let staking = try XCTUnwrap(plan.first)
        ledger.markHandled(staking, now: Fixtures.morning)
        XCTAssertTrue(ledger.scheduled.isEmpty)
        XCTAssertEqual(ledger.history.count, 1)
    }

    func testLedgerRoundTripsAsJSON() throws {
        var ledger = NudgeLedger()
        ledger.replan(engine: engine, state: stakingState(), now: Fixtures.morning)
        ledger.settle(now: Fixtures.at(0, 8))
        let data = try JSONEncoder().encode(ledger)
        let back = try JSONDecoder().decode(NudgeLedger.self, from: data)
        XCTAssertEqual(back.delivered, ledger.delivered)
        XCTAssertEqual(back.history, ledger.history)
    }

    func testNameMatching() {
        XCTAssertEqual(NameMatch.index(of: "the Sungold", in: ["Big Beef", "Sungold", "Sungold 2"]), 1)
        XCTAssertEqual(NameMatch.index(of: "tomato", in: ["Tomato bed", "Tomatoes"]), 1)
        XCTAssertEqual(NameMatch.index(of: "back bed", in: ["Front bed", "Back Bed"]), 1)
        XCTAssertNil(NameMatch.index(of: "basil", in: ["Big Beef"]))
        XCTAssertNil(NameMatch.index(of: " ", in: ["Big Beef"]))
    }
}
