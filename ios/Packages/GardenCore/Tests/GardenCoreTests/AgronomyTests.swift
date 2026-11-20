import XCTest
@testable import GardenCore

final class AgronomyTests: XCTestCase {
    let cal = Fixtures.calendar

    func testGrowingDegreeDays() {
        XCTAssertEqual(Agronomy.gdd(highF: 86, lowF: 50), 18)
        XCTAssertEqual(Agronomy.gdd(highF: 95, lowF: 40), 18) // capped at 86, floored at 50
        XCTAssertEqual(Agronomy.gdd(highF: 60, lowF: 40), 5)
        XCTAssertEqual(Agronomy.gdd(highF: 45, lowF: 30), 0)
        XCTAssertEqual(Agronomy.gdd(highF: 60, lowF: 45, baseF: 40), 12.5)
    }

    func testGDDTotalCountsMissingDays() {
        var weather = Fixtures.weather(past: 5, future: 0, high: 80, low: 60)
        weather.days.removeAll { $0.day == Fixtures.day(-3) }
        let total = Agronomy.gddTotal(weather.days, from: Fixtures.day(-5), through: Fixtures.day(-1), baseF: 50, calendar: cal)
        XCTAssertEqual(total.total, 80) // 4 days x 20
        XCTAssertEqual(total.missingDays, 1)
        XCTAssertEqual(Agronomy.gddTotal(weather.days, from: Fixtures.day(1), through: Fixtures.day(0), baseF: 50, calendar: cal).total, 0)
    }

    func testWaterAmountsFromText() {
        XCTAssertEqual(WaterAmount.inches(amount: "2 gallons", what: "", areaSqFt: 32), 2 / (0.623 * 32), accuracy: 1e-9)
        XCTAssertEqual(WaterAmount.inches(amount: "3 gal", what: "", areaSqFt: nil), 3 / (0.623 * 32), accuracy: 1e-9)
        XCTAssertEqual(WaterAmount.inches(amount: "10 gallons", what: "", areaSqFt: 2), 3) // capped
        XCTAssertEqual(WaterAmount.inches(amount: "1 inch", what: "", areaSqFt: 32), 1)
        XCTAssertEqual(WaterAmount.inches(amount: "1/2 in", what: "", areaSqFt: 32), 0.5)
        XCTAssertEqual(WaterAmount.inches(amount: "", what: "about half an inch", areaSqFt: 32), 0.5)
        XCTAssertEqual(WaterAmount.inches(amount: "", what: "an inch or so", areaSqFt: 32), 1)
        XCTAssertEqual(WaterAmount.inches(amount: "", what: "deep soak", areaSqFt: 32), WaterAmount.deep)
        XCTAssertEqual(WaterAmount.inches(amount: "", what: "quick sprinkle", areaSqFt: 32), WaterAmount.light)
        XCTAssertEqual(WaterAmount.inches(amount: "", what: "watered", areaSqFt: 32), WaterAmount.normal)
    }

    func testCapacityAndMultipliers() {
        XCTAssertEqual(WaterModel.capacity(soil: .loam, kind: .raised), 0.9, accuracy: 1e-9)
        XCTAssertEqual(WaterModel.capacity(soil: .sand, kind: .container), 0.3, accuracy: 1e-9)
        var bed = Fixtures.bed(kind: .inGround)
        XCTAssertEqual(WaterModel.etMultiplier(bed: bed), 1.0)
        bed.mulch = "straw"
        XCTAssertEqual(WaterModel.etMultiplier(bed: bed), 0.8, accuracy: 1e-9)
        XCTAssertEqual(WaterModel.cropCoefficient(for: []), 0.4)
        XCTAssertEqual(WaterModel.effectiveRain(0.05), 0)
        XCTAssertEqual(WaterModel.effectiveRain(1.05), 0.9, accuracy: 1e-9)
    }

    private func setup() -> (BedInfo, [PlantInfo]) {
        let bed = Fixtures.bed()
        return (bed, [Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 60, stage: .fruiting)])
    }

    private func state(_ bed: BedInfo, _ plants: [PlantInfo], journal: [JournalInfo] = [], weather: WeatherReport?) -> WaterState {
        WaterModel.state(bed: bed, plants: plants, journal: journal, weather: weather, today: Fixtures.today, calendar: cal)
    }

    func testUnknownWithoutWeather() {
        let (bed, plants) = setup()
        XCTAssertEqual(state(bed, plants, weather: nil).status, .unknown)
    }

    func testHotDryWeeksDryTheBedOut() {
        let (bed, plants) = setup()
        let ws = state(bed, plants, weather: Fixtures.weather(et0: 0.25))
        XCTAssertEqual(ws.status, .dry)
        XCTAssertEqual(ws.deficitInches, ws.capacityInches, accuracy: 1e-9)
        XCTAssertNil(ws.lastRefillDay)
    }

    func testWateringTodayRefills() {
        let (bed, plants) = setup()
        let water = JournalInfo(day: Fixtures.today, kind: .watering, what: "Deep soak", bedID: bed.id, waterInches: 1)
        let ws = state(bed, plants, journal: [water], weather: Fixtures.weather(et0: 0.25))
        XCTAssertEqual(ws.status, .ok)
        XCTAssertEqual(ws.deficitInches, 0)
        XCTAssertEqual(ws.lastRefillDay, Fixtures.today)
    }

    func testWateringLoggedOnAPlantCountsForItsBed() {
        let (bed, plants) = setup()
        let water = JournalInfo(day: Fixtures.today, kind: .watering, what: "Watered", amount: "1 inch", plantID: plants[0].id)
        XCTAssertEqual(state(bed, plants, journal: [water], weather: Fixtures.weather(et0: 0.25)).status, .ok)
    }

    func testFingerTestResetsTheEstimate() {
        let (bed, plants) = setup()
        let check = JournalInfo(day: Fixtures.day(-1), kind: .moistureCheck, what: "Finger test", bedID: bed.id, moisture: .moist)
        let ws = state(bed, plants, journal: [check], weather: Fixtures.weather(et0: 0.25))
        XCTAssertEqual(ws.deficitInches, 0.9 * 0.25, accuracy: 1e-9)
        XCTAssertEqual(ws.status, .ok)
        XCTAssertEqual(ws.lastRefillDay, Fixtures.day(-1))
    }

    func testRainRefillsAndProjectionDriesOut() {
        let (bed, plants) = setup()
        let weather = Fixtures.weather(et0: 0.25) { offset, d in
            if offset == -1 { d.rainInches = 1.5 }
        }
        let ws = state(bed, plants, weather: weather)
        // 1.5 in of rain (1.305 effective) more than refills 0.9 in of capacity.
        XCTAssertEqual(ws.deficitInches, 0, accuracy: 1e-9)
        XCTAssertEqual(ws.lastRefillDay, Fixtures.day(-1))
        // Tomato at fruiting: Kc 1.05 x 1.15, raised bed x 1.05, so about 0.317 in a day.
        let daily = 0.25 * 1.05 * 1.15 * 1.05
        XCTAssertEqual(ws.projected.count, 4)
        XCTAssertEqual(ws.projected[0].deficitInches, daily, accuracy: 1e-9)
        XCTAssertEqual(ws.projected[0].status, .ok)
        XCTAssertEqual(ws.projected[1].status, .dry)
    }

    func testStatusThresholds() {
        XCTAssertEqual(WaterModel.status(fraction: 0.2), .ok)
        XCTAssertEqual(WaterModel.status(fraction: 0.45), .check)
        XCTAssertEqual(WaterModel.status(fraction: 0.7), .dry)
    }
}
