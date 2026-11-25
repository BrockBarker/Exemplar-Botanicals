import XCTest
@testable import GardenCore

final class ToolboxTests: XCTestCase {
    func testFreeBeforeLowCostBeforeBranded() {
        let ranked = Toolbox.ranked(for: .feed, inventory: [])
        XCTAssertEqual(ranked.first?.id, "compost")
        XCTAssertEqual(ranked.map { $0.tier }, ranked.map { $0.tier }.sorted())
        XCTAssertEqual(ranked.filter { $0.tier == .free }.map { $0.id }, ["compost", "comfrey_tea"])
        XCTAssertTrue(ranked.filter { $0.tier == .branded }.allSatisfy { !$0.price.isEmpty })
    }

    func testUrineOnlyWhenAskedFor() {
        XCTAssertFalse(Toolbox.ranked(for: .feed, inventory: []).contains { $0.id == "urine" })
        let asked = Toolbox.ranked(for: .feed, inventory: [], includeUrine: true)
        XCTAssertEqual(asked.filter { $0.tier == .free }.map { $0.id }, ["compost", "comfrey_tea", "urine"])
    }

    func testPestOptionsStartGentle() {
        let ranked = Toolbox.ranked(for: .pests, inventory: [InventoryInfo(name: "Safer insecticidal soap", category: .pestControl)])
        XCTAssertEqual(ranked.first?.tier, .owned)
        XCTAssertEqual(ranked.dropFirst().prefix(2).map { $0.id }, ["hand_pick", "water_blast"])
        XCTAssertFalse(ranked.contains { $0.id == "insecticidal_soap" })
    }

    func testEveryCropHasCareNotes() {
        for crop in CropCatalog.all {
            XCTAssertNotNil(CropCatalog.careByID[crop.id], "\(crop.id) needs a CropCare entry")
        }
        XCTAssertEqual(CropCatalog.profile(for: "tomato").care.firstHarvestDays, 70)
        XCTAssertNil(CropCatalog.care(for: "nope").firstHarvestDays)
    }

    func testOwnedItemsComeFirstAndReplaceTheirGenericEntry() {
        let inventory = [
            InventoryInfo(name: "Rake", category: .tool),
            InventoryInfo(name: "Neptune's Harvest Fish & Seaweed", category: .fertilizer),
            InventoryInfo(name: "Mystery bloom booster", category: .fertilizer),
        ]
        let ranked = Toolbox.ranked(for: .feed, inventory: inventory)
        XCTAssertEqual(ranked[0].name, "Neptune's Harvest Fish & Seaweed")
        XCTAssertEqual(ranked[0].tier, .owned)
        XCTAssertEqual(ranked[0].inventoryItemName, "Neptune's Harvest Fish & Seaweed")
        XCTAssertTrue(ranked[0].howTo.contains("tablespoon"))
        XCTAssertEqual(ranked[1].name, "Mystery bloom booster")
        XCTAssertEqual(ranked[1].howTo, "Use it as the label directs for this.")
        XCTAssertEqual(ranked[2].id, "compost")
        XCTAssertFalse(ranked.contains { $0.id == "fish_seaweed" })
        XCTAssertFalse(ranked.contains { $0.name == "Rake" })
    }

    func testFoliarAndFrostMatching() {
        let foliar = Toolbox.ranked(for: .foliar, inventory: [InventoryInfo(name: "Maxicrop liquid seaweed", category: .foliar)])
        XCTAssertEqual(foliar[0].tier, .owned)
        XCTAssertFalse(foliar.contains { $0.id == "kelp" })
        XCTAssertEqual(foliar[1].id, "comfrey_foliar")
        XCTAssertFalse(foliar.contains { $0.id == "compost_tea" }, "David finds compost tea more effort than result")

        let frost = Toolbox.ranked(for: .frostCover, inventory: [InventoryInfo(name: "Old bedsheets", category: .other)])
        XCTAssertEqual(frost.map { $0.tier }, [.owned, .lowCost])
        XCTAssertEqual(frost[1].id, "row_cover")
    }

    func testCropCatalog() {
        let ids = CropCatalog.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "crop ids must be unique")
        XCTAssertEqual(CropCatalog.profile(for: "tomato").name, "Tomato")
        XCTAssertEqual(CropCatalog.profile(for: "nope").id, "other")
        XCTAssertEqual(CropCatalog.profile(for: nil).id, "other")
        XCTAssertEqual(CropCatalog.guess(from: "Sungold")?.id, "cherry_tomato")
        XCTAssertEqual(CropCatalog.guess(from: "Big Beef tomato")?.id, "tomato")
        XCTAssertEqual(CropCatalog.guess(from: "Snow peas")?.id, "pea")
        XCTAssertEqual(CropCatalog.guess(from: "Elberta peach")?.id, "fruit_tree")
        XCTAssertNil(CropCatalog.guess(from: "Mystery vine"))
    }

    /// The backend lists these ids in the update_plant tool; keep the two in sync.
    func testCropIDsMatchTheBackendList() {
        let backend = "tomato, cherry_tomato, pepper, eggplant, cucumber, summer_squash, winter_squash, melon, corn, bush_bean, pole_bean, pea, lettuce, spinach, kale, chard, cabbage, broccoli, cauliflower, carrot, beet, radish, onion, garlic, potato, sweet_potato, okra, strawberry, blueberry, bramble, basil, perennial_herb, annual_herb, flower_annual, dahlia, rose, fruit_tree, citrus"
        let expected = backend.components(separatedBy: ", ")
        XCTAssertEqual(CropCatalog.all.map { $0.id }, expected)
    }

    func testCropCoefficients() {
        let tomato = CropCatalog.profile(for: "tomato")
        XCTAssertEqual(tomato.cropCoefficient(at: .fruiting), 1.05 * 1.15, accuracy: 1e-9)
        XCTAssertLessThan(tomato.cropCoefficient(at: .seedling), tomato.cropCoefficient(at: .flowering))
    }
}
