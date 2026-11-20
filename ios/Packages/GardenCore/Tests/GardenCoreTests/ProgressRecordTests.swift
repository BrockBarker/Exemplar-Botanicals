import XCTest
@testable import GardenCore

final class ProgressRecordTests: XCTestCase {
    let cal = Fixtures.calendar
    let bedA = UUID()
    let bedB = UUID()
    let tomato = UUID()
    let pepper = UUID()
    let basil = UUID()

    private func photo(_ offset: Int, plant: UUID? = nil, bed: UUID? = nil, hour: Int = 9) -> ProgressPhoto {
        ProgressPhoto(day: Fixtures.day(offset), bedID: bed, plantID: plant, created: Fixtures.at(offset, hour))
    }

    private func treatment(
        _ offset: Int, _ kind: JournalKind = .feeding, _ what: String = "Fish emulsion", plant: UUID? = nil, bed: UUID? = nil
    ) -> JournalInfo {
        JournalInfo(day: Fixtures.day(offset), kind: kind, what: what, bedID: bed, plantID: plant)
    }

    // MARK: Membership

    func testWhatCountsAsATreatment() {
        XCTAssertTrue(JournalKind.feeding.isTreatment)
        XCTAssertTrue(JournalKind.foliarSpray.isTreatment)
        XCTAssertTrue(JournalKind.amendment.isTreatment)
        XCTAssertTrue(JournalKind.pestOrDisease.isTreatment)
        XCTAssertFalse(JournalKind.watering.isTreatment)
        XCTAssertFalse(JournalKind.observation.isTreatment)
        XCTAssertFalse(JournalKind.harvest.isTreatment)
    }

    func testPlantRecordIncludesItsOwnAndBedWideEntries() {
        let scope = RecordScope.plant(tomato, bedID: bedA)
        XCTAssertTrue(ProgressRecord.belongs(kind: .watering, bedID: bedA, plantID: tomato, to: scope))
        XCTAssertTrue(ProgressRecord.belongs(kind: .observation, bedID: nil, plantID: tomato, to: scope))
        XCTAssertFalse(ProgressRecord.belongs(kind: .feeding, bedID: bedA, plantID: pepper, to: scope))
        XCTAssertTrue(ProgressRecord.belongs(kind: .mulching, bedID: bedA, plantID: nil, to: scope))
        XCTAssertFalse(ProgressRecord.belongs(kind: .mulching, bedID: bedB, plantID: nil, to: scope))
        // Garden-wide: only treatments.
        XCTAssertTrue(ProgressRecord.belongs(kind: .feeding, bedID: nil, plantID: nil, to: scope))
        XCTAssertFalse(ProgressRecord.belongs(kind: .watering, bedID: nil, plantID: nil, to: scope))
    }

    func testBedRecordIncludesItsPlantsEvenIfLoggedBeforeTheyMoved() {
        let scope = RecordScope.bed(bedA, plantIDs: [tomato, pepper])
        XCTAssertTrue(ProgressRecord.belongs(kind: .feeding, bedID: nil, plantID: tomato, to: scope))
        XCTAssertTrue(ProgressRecord.belongs(kind: .watering, bedID: bedA, plantID: nil, to: scope))
        XCTAssertTrue(ProgressRecord.belongs(kind: .harvest, bedID: bedA, plantID: basil, to: scope), "logged while basil was here")
        XCTAssertFalse(ProgressRecord.belongs(kind: .feeding, bedID: bedB, plantID: basil, to: scope))
        XCTAssertFalse(ProgressRecord.belongs(kind: .feeding, bedID: nil, plantID: basil, to: scope))
        XCTAssertTrue(ProgressRecord.belongs(kind: .foliarSpray, bedID: nil, plantID: nil, to: scope))
        XCTAssertFalse(ProgressRecord.belongs(kind: .observation, bedID: nil, plantID: nil, to: scope))
    }

    func testGalleryMembership() {
        let plantScope = RecordScope.plant(tomato, bedID: bedA)
        XCTAssertTrue(ProgressRecord.belongs(photo(0, plant: tomato, bed: bedA), to: plantScope))
        XCTAssertFalse(ProgressRecord.belongs(photo(0, bed: bedA), to: plantScope), "a bed photo isn't the plant's")
        let bedScope = RecordScope.bed(bedA, plantIDs: [tomato])
        XCTAssertTrue(ProgressRecord.belongs(photo(0, bed: bedA), to: bedScope))
        XCTAssertTrue(ProgressRecord.belongs(photo(0, plant: tomato), to: bedScope))
        XCTAssertFalse(ProgressRecord.belongs(photo(0, plant: basil, bed: bedB), to: bedScope))
    }

    // MARK: Before and after

    func testPicksTheClosestPhotosAroundATreatment() {
        let feed = treatment(0, plant: tomato, bed: bedA)
        let spray = treatment(4, .foliarSpray, "Kelp spray", plant: tomato, bed: bedA)
        let lateSpray = treatment(11, .foliarSpray, "Kelp spray", plant: tomato, bed: bedA)
        let photos = [
            photo(-9, plant: tomato, bed: bedA),
            photo(-2, plant: tomato, bed: bedA),
            photo(5, plant: tomato, bed: bedA),
            photo(11, plant: tomato, bed: bedA),
            photo(20, plant: tomato, bed: bedA),
        ]
        let result = ProgressRecord.comparisons(treatments: [feed, spray, lateSpray], photos: photos, calendar: cal)
        let forFeed = result.first { $0.treatment.id == feed.id }
        XCTAssertEqual(forFeed?.before.day, Fixtures.day(-2))
        XCTAssertEqual(forFeed?.after.day, Fixtures.day(11), "closest to 10 days after")
        XCTAssertEqual(forFeed?.daysAfterTreatment(calendar: cal), 11)
        XCTAssertEqual(forFeed?.alsoApplied.map(\.id), [spray.id], "a spray on the after-photo day doesn't count")
    }

    func testNeedsABeforePhotoWithinTwoWeeks() {
        let feed = treatment(0, plant: tomato)
        let photos = [photo(-15, plant: tomato), photo(10, plant: tomato)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [feed], photos: photos, calendar: cal).isEmpty)
    }

    func testNeedsAnAfterPhotoAtLeastThreeDaysLater() {
        let feed = treatment(0, plant: tomato)
        let tooSoon = [photo(-1, plant: tomato), photo(2, plant: tomato)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [feed], photos: tooSoon, calendar: cal).isEmpty)
        let tooLate = [photo(-1, plant: tomato), photo(31, plant: tomato)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [feed], photos: tooLate, calendar: cal).isEmpty)
    }

    func testAPhotoOnTheTreatmentDayCountsAsBefore() {
        let feed = treatment(0, plant: tomato)
        let photos = [photo(0, plant: tomato), photo(7, plant: tomato)]
        let result = ProgressRecord.comparisons(treatments: [feed], photos: photos, calendar: cal)
        XCTAssertEqual(result.first?.before.day, Fixtures.day(0))
        XCTAssertEqual(result.first?.after.day, Fixtures.day(7))
    }

    func testWateringIsNotATreatment() {
        let water = treatment(0, .watering, "Deep soak", plant: tomato)
        let photos = [photo(-1, plant: tomato), photo(8, plant: tomato)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [water], photos: photos, calendar: cal).isEmpty)
    }

    func testAPlantTreatmentOnlyUsesThatPlantsPhotos() {
        let feed = treatment(0, plant: tomato, bed: bedA)
        let photos = [photo(-1, plant: pepper, bed: bedA), photo(9, plant: pepper, bed: bedA)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [feed], photos: photos, calendar: cal).isEmpty)
    }

    func testABedTreatmentNeverMixesPlants() {
        let compost = treatment(0, .amendment, "Compost side-dress", bed: bedA)
        // Tomato has only a before photo, pepper only an after photo: no honest pair.
        let mixed = [photo(-1, plant: tomato, bed: bedA), photo(10, plant: pepper, bed: bedA)]
        XCTAssertTrue(ProgressRecord.comparisons(treatments: [compost], photos: mixed, calendar: cal).isEmpty)

        // Add a pepper before photo: now the pepper pair is used.
        let withPepper = mixed + [photo(-3, plant: pepper, bed: bedA)]
        let result = ProgressRecord.comparisons(treatments: [compost], photos: withPepper, calendar: cal)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.before.plantID, pepper)
        XCTAssertEqual(result.first?.after.plantID, pepper)
    }

    func testABedTreatmentPrefersThePairClosestToTenDays() {
        let compost = treatment(0, .amendment, "Compost", bed: bedA)
        let photos = [
            photo(-1, plant: tomato, bed: bedA), photo(4, plant: tomato, bed: bedA),
            photo(-1, plant: pepper, bed: bedA), photo(9, plant: pepper, bed: bedA),
        ]
        let result = ProgressRecord.comparisons(treatments: [compost], photos: photos, calendar: cal)
        XCTAssertEqual(result.first?.after.plantID, pepper)
    }

    func testGardenWideTreatmentUsesWhateverPhotosAreInScope() {
        let tea = treatment(0, .foliarSpray, "Compost tea")
        let photos = [photo(-2, bed: bedA), photo(12, bed: bedA)]
        let result = ProgressRecord.comparisons(treatments: [tea], photos: photos, calendar: cal)
        XCTAssertEqual(result.count, 1)
    }

    func testComparisonsAreNewestFirst() {
        let early = treatment(-20, plant: tomato)
        let late = treatment(0, plant: tomato)
        let photos = [photo(-21, plant: tomato), photo(-10, plant: tomato), photo(-1, plant: tomato), photo(10, plant: tomato)]
        let result = ProgressRecord.comparisons(treatments: [early, late], photos: photos, calendar: cal)
        XCTAssertEqual(result.map(\.treatment.id), [late.id, early.id])
    }

    // MARK: Groups

    func testGroupsRepeatUsesOfTheSameTreatment() {
        let photos = [
            photo(-31, plant: tomato), photo(-20, plant: tomato), photo(-1, plant: tomato), photo(10, plant: tomato),
        ]
        let first = treatment(-30, plant: tomato, bed: nil)
        let second = JournalInfo(day: Fixtures.day(0), kind: .feeding, what: "fish  emulsion.", plantID: tomato)
        let spray = treatment(-1, .foliarSpray, "Kelp", plant: tomato)
        let comparisons = ProgressRecord.comparisons(treatments: [first, second, spray], photos: photos, calendar: cal)
        let groups = ProgressRecord.groups(comparisons)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.title, "fish  emulsion.", "titled by the most recent use")
        XCTAssertEqual(groups.first?.comparisons.map(\.treatment.id), [second.id, first.id])
        XCTAssertEqual(groups.last?.kind, .foliarSpray)
    }

    // MARK: Captions

    func testPhotoContextListsTreatmentsSinceThePreviousPhoto() {
        let photos = [
            photo(-14, plant: tomato, bed: bedA),
            photo(-7, plant: pepper, bed: bedA),
            photo(0, plant: tomato, bed: bedA),
        ]
        let treatments = [
            treatment(-20, plant: tomato), // before the previous photo
            treatment(-14, .foliarSpray, "Kelp", plant: tomato), // same day as previous photo: counts
            treatment(-5, .amendment, "Compost", bed: bedA), // bed-wide: counts
            treatment(-3, plant: pepper, bed: bedA), // another plant
            treatment(-2, .watering, "Soak", plant: tomato), // not a treatment
            treatment(0, .pruning, "Suckers", plant: tomato), // same day as this photo: after it
        ]
        let context = ProgressRecord.context(for: photos[2], photos: photos, treatments: treatments, calendar: cal)
        XCTAssertEqual(context.previous?.id, photos[0].id)
        XCTAssertEqual(context.treatments.map(\.what), ["Kelp", "Compost"])
    }

    func testFirstPhotoLooksBackThirtyDays() {
        let first = photo(0, plant: tomato)
        let treatments = [treatment(-31, plant: tomato), treatment(-30, .amendment, "Worm castings", plant: tomato)]
        let context = ProgressRecord.context(for: first, photos: [first], treatments: treatments, calendar: cal)
        XCTAssertNil(context.previous)
        XCTAssertEqual(context.treatments.map(\.what), ["Worm castings"])
    }

    func testSameDayPhotosAreOrderedByTime() {
        let morning = photo(0, plant: tomato, hour: 8)
        let evening = photo(0, plant: tomato, hour: 19)
        let context = ProgressRecord.context(for: evening, photos: [evening, morning], treatments: [], calendar: cal)
        XCTAssertEqual(context.previous?.id, morning.id)
        let back = ProgressRecord.context(for: morning, photos: [evening, morning], treatments: [], calendar: cal)
        XCTAssertNil(back.previous)
    }
}
