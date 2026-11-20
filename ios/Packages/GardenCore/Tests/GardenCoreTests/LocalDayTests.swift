import XCTest
@testable import GardenCore

final class LocalDayTests: XCTestCase {
    let cal = Fixtures.calendar

    func testParsesAndPrints() {
        let d = LocalDay("2026-07-14")
        XCTAssertEqual(d, LocalDay(year: 2026, month: 7, day: 14))
        XCTAssertEqual(d?.string, "2026-07-14")
        XCTAssertEqual(LocalDay("2026-03-05T06:00")?.string, "2026-03-05")
        XCTAssertNil(LocalDay("2026-13-01"))
        XCTAssertNil(LocalDay("July 4"))
    }

    func testCodableAsString() throws {
        let data = try JSONEncoder().encode([Fixtures.today])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-07-14\"]")
        let back = try JSONDecoder().decode([LocalDay].self, from: data)
        XCTAssertEqual(back, [Fixtures.today])
    }

    func testDayMathAcrossDaylightSaving() {
        let before = LocalDay(year: 2026, month: 3, day: 7)
        XCTAssertEqual(before.adding(days: 1, calendar: cal).string, "2026-03-08")
        XCTAssertEqual(before.adding(days: 2, calendar: cal).string, "2026-03-09")
        XCTAssertEqual(before.days(to: LocalDay(year: 2026, month: 3, day: 21), calendar: cal), 14)
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1, calendar: cal).string, "2027-01-01")
        XCTAssertEqual(Fixtures.today.adding(days: -14, calendar: cal).string, "2026-06-30")
    }

    func testDateAtMinuteUsesGardenTimeZone() {
        let date = Fixtures.today.date(atMinute: 7 * 60 + 30, in: cal)
        // Chicago is UTC-5 in July.
        XCTAssertEqual(date.timeIntervalSince1970, 1_784_032_200)
        XCTAssertEqual(cal.minuteOfDay(date), 450)
        XCTAssertEqual(LocalDay(date, calendar: cal), Fixtures.today)
    }

    func testSpokenNames() {
        let t = Fixtures.today
        XCTAssertEqual(t.spokenName(relativeTo: t, calendar: cal), "today")
        XCTAssertEqual(t.adding(days: 1, calendar: cal).spokenName(relativeTo: t, calendar: cal), "tomorrow")
        XCTAssertEqual(t.adding(days: -1, calendar: cal).spokenName(relativeTo: t, calendar: cal), "yesterday")
        XCTAssertEqual(t.adding(days: 2, calendar: cal).spokenName(relativeTo: t, calendar: cal), "Thursday")
        XCTAssertEqual(t.adding(days: 10, calendar: cal).spokenName(relativeTo: t, calendar: cal), "Friday 7/24")
    }
}
