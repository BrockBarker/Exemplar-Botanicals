import Foundation

// David's care for new plantings (backend/persona/method.md): water nearly every day early on
// so they never wilt, and a small bottle of liquid kelp and fish hydrolysate about once a week
// for the first 2 or 3 weeks after they go out in the beds, early in the morning before the dew
// dries, and never within a couple of weeks of harvest.

extension NudgeEngine {
    /// How long a planting counts as new: daily water checks and weekly sprays stop after this.
    static let newPlantDays = 21
    /// David sprays new transplants about once a week.
    static let newPlantSprayEveryDays = 7

    /// Days since planting, when the plant has a planting date and it's still new on `day`.
    func newPlantAge(_ plant: PlantInfo, on day: LocalDay) -> Int? {
        guard let planted = plant.plantedOn else { return nil }
        let age = planted.days(to: day, calendar: calendar)
        return (0...Self.newPlantDays).contains(age) ? age : nil
    }

    /// A daily finger-test reminder for beds with new plantings, for their first 3 weeks.
    /// Skips days the bed was already checked or watered, days with a good soaking rain, and
    /// days the regular moisture nudges already cover (`covered`).
    func newPlantWater(_ state: GardenState, today: LocalDay, covered: [Nudge], horizonDays: Int = 7) -> [Nudge] {
        let young = state.plants.filter { $0.stage != .mature && $0.stage != .dormant }
        guard young.contains(where: { newPlantAge($0, on: today) != nil }) else { return [] }

        var out: [Nudge] = []
        for offset in 0..<max(1, horizonDays) {
            let day = today.adding(days: offset, calendar: calendar)
            if soakingRain(state, on: day, today: today) { continue }
            let coveredBeds = Set(covered.filter { LocalDay($0.fireDate, calendar: calendar) == day }.flatMap { $0.bedIDs })

            var beds: [BedInfo] = []
            var loose: [PlantInfo] = []
            for bed in state.beds where !coveredBeds.contains(bed.id) {
                let plants = young.filter { $0.bedID == bed.id && newPlantAge($0, on: day) != nil }
                guard !plants.isEmpty else { continue }
                if offset == 0 && checkedOrWatered(state, bed: bed, plants: plants, on: day) { continue }
                beds.append(bed)
            }
            for plant in young where plant.bedID == nil || !state.beds.contains(where: { $0.id == plant.bedID }) {
                guard newPlantAge(plant, on: day) != nil else { continue }
                if offset == 0 && checkedOrWatered(state, bed: nil, plants: [plant], on: day) { continue }
                loose.append(plant)
            }
            guard !beds.isEmpty || !loose.isEmpty else { continue }

            let names = beds.map { $0.name } + loose.map { $0.name }
            let title = beds.isEmpty
                ? "Water check: the new \(NudgeText.list(loose.map { $0.name }))"
                : "Water check: new plants in \(NudgeText.list(names))"
            out.append(Nudge(
                kind: .moistureCheck,
                dedupeKey: "new_plant_water_\(day.string)",
                cooldownDays: 0,
                priority: 65,
                fireDate: at(day, settings.deliveryMinute),
                expires: at(day, 21 * 60),
                title: title,
                body: "New plants should never wilt. Push a finger 2 inches into the soil: dry means water gently until it soaks in.",
                detail: "Early in a plant's life I water nearly every day so it isn't stressed at all, then I slack off once it's settled in. " +
                    "These daily checks stop \(Self.newPlantDays / 7) weeks after planting. Logging what you find keeps the app's water estimate for the bed accurate.",
                bedIDs: beds.map { $0.id },
                plantIDs: loose.map { $0.id },
                log: SuggestedLog(kind: .moistureCheck, what: "Finger test", bedIDs: beds.map { $0.id }, plantIDs: loose.map { $0.id })
            ))
        }
        return out
    }

    /// David's weekly kelp and fish hydrolysate spray for new transplants, for their first 3 weeks.
    func newPlantSpray(_ state: GardenState, today: LocalDay, now: Date, horizonDays: Int = 7) -> [Nudge] {
        var due: [(plant: PlantInfo, day: LocalDay)] = []
        for plant in state.plants where plant.stage.isActive {
            guard let planted = plant.plantedOn, newPlantAge(plant, on: today) != nil,
                  !nearHarvest(plant, state: state, today: today) else { continue }
            let bedName = state.bedName(for: plant)
            let lastSpray = state.journal
                .filter { $0.kind == .foliarSpray && $0.day >= planted && $0.day <= today && $0.applies(to: plant, bedName: bedName) }
                .map { $0.day }
                .max()
            let next = (lastSpray ?? planted).adding(days: Self.newPlantSprayEveryDays, calendar: calendar)
            guard planted.days(to: next, calendar: calendar) <= Self.newPlantDays else { continue }
            due.append((plant: plant, day: max(next, today)))
        }
        guard let first = due.map({ $0.day }).min(), today.days(to: first, calendar: calendar) < horizonDays else { return [] }
        // Spray everything that comes due within a few days in one go.
        let batch = due.filter { first.days(to: $0.day, calendar: calendar) <= 3 }.map { $0.plant }
        let names = NudgeText.list(batch.map { $0.name })

        // Without a forecast, remind at the usual time on the day it's due.
        var fire = at(first, settings.deliveryMinute)
        var lead = "Early in the morning, before the dew dries,"
        var expires = at(first.adding(days: 3, calendar: calendar), 10 * 60)
        if let hours = state.weather?.hours, !hours.isEmpty,
           let window = bestFoliarWindow(hours, after: max(now.addingTimeInterval(3600), first.startDate(in: calendar)), today: first) {
            let windowDay = LocalDay(window.start, calendar: calendar)
            fire = foliarFireDate(for: window, now: now)
            lead = "\(windowDay.spokenName(relativeTo: today, calendar: calendar).capitalizedFirst) \(NudgeText.hourRange(window.start, window.end, calendar: calendar)) looks calm and cool. Before the dew dries,"
            expires = window.end
        }

        let options = Toolbox.ranked(for: .foliar, inventory: state.inventory)
        return [Nudge(
            kind: .foliar,
            dedupeKey: "new_plant_spray",
            cooldownDays: 3,
            priority: 45,
            fireDate: fire,
            expires: expires,
            title: "Kelp and fish spray for the new \(names)",
            body: "\(lead) mist the leaves, tops and undersides, with liquid kelp and fish hydrolysate from a small spray bottle.",
            detail: NudgeText.optionsDetail(
                intro: "I spray new transplants about once a week for their first 2 or 3 weeks in the beds, with the same small bottle I use on seedlings. " + Self.foliarTiming,
                options: options,
                outro: "These reminders stop \(Self.newPlantDays / 7) weeks after planting, and skip anything within a couple of weeks of harvest."
            ),
            plantIDs: batch.map { $0.id },
            log: SuggestedLog(kind: .foliarSpray, what: "Kelp and fish hydrolysate spray", plantIDs: batch.map { $0.id })
        )]
    }

    /// Already checked or watered on this day (the bed, or one of these plants).
    private func checkedOrWatered(_ state: GardenState, bed: BedInfo?, plants: [PlantInfo], on day: LocalDay) -> Bool {
        state.journal.contains { entry in
            guard entry.day == day, entry.kind == .watering || entry.kind == .moistureCheck else { return false }
            if let bed = bed, entry.applies(to: bed) { return true }
            return plants.contains { entry.applies(to: $0, bedName: state.bedName(for: $0)) }
        }
    }

    /// A good soaking rain the day before, or one that's very likely on the day.
    private func soakingRain(_ state: GardenState, on day: LocalDay, today: LocalDay) -> Bool {
        if let before = forecastDay(state, day.adding(days: -1, calendar: calendar)), (before.rainInches ?? 0) >= 0.5,
           before.day < today || (before.rainChance ?? 100) >= 60 {
            return true
        }
        guard let w = forecastDay(state, day) else { return false }
        return (w.rainInches ?? 0) >= 0.4 && (w.rainChance ?? 100) >= 60
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
