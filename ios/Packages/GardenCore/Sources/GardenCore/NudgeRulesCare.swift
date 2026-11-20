import Foundation

// Nudges about the rest of the garden's care, beyond water, weather and food: harvest timing,
// pest checks, pruning, succession sowing and the end-of-season wrap-up. Crop specifics come
// from CropCare.

extension NudgeEngine {
    /// Plants worth looking over for something to pick, and ones whose first harvest is close.
    func harvest(_ state: GardenState, today: LocalDay) -> [Nudge] {
        var ready: [PlantInfo] = []
        var soon: [(plant: PlantInfo, days: Int)] = []

        for plant in state.plants where plant.stage != .seed && plant.stage != .dormant {
            let care = plant.crop.care
            let bedName = state.bedName(for: plant)
            let lastHarvest = state.journal
                .filter { $0.kind == .harvest && $0.applies(to: plant, bedName: bedName) }
                .map { $0.day }
                .max()
            let age = plant.plantedOn.map { $0.days(to: today, calendar: calendar) }

            if let every = care.pickEveryDays {
                // Keeps producing: remind once it's been a picking interval since the last harvest.
                if let last = lastHarvest, last.days(to: today, calendar: calendar) < every { continue }
            } else if let last = lastHarvest, plant.plantedOn.map({ last >= $0 }) ?? true {
                // One harvest and done.
                continue
            }

            let producing = plant.stage == .mature || (plant.stage == .fruiting && care.pickEveryDays != nil)
            if producing {
                ready.append(plant)
                continue
            }
            guard plant.stage != .seedling, let start = care.firstHarvestDays, let age = age else { continue }
            let until = start - age
            if until <= 0 {
                // Past the usual first harvest. A one-time crop this far past was probably picked
                // without being logged, so stop asking.
                if care.pickEveryDays == nil && -until > 45 { continue }
                ready.append(plant)
            } else if until <= 7 {
                soon.append((plant, until))
            }
        }
        guard !ready.isEmpty || !soon.isEmpty else { return [] }

        func line(_ plant: PlantInfo) -> String {
            let care = plant.crop.care
            var text = "\(plant.name): ready when \(care.readyWhen)."
            if let every = care.pickEveryDays {
                text += " Once it starts, pick every \(every == 1 ? "day" : "\(every) days") or so; regular picking keeps it producing."
            }
            return text
        }

        if !ready.isEmpty {
            let names = NudgeText.list(ready.map { $0.name })
            var detail = ready.map(line)
            if !soon.isEmpty {
                detail.append("Coming up soon: " + NudgeText.list(soon.map { $0.plant.name }) + ".")
            }
            detail.append("Pick in the cool of the morning, and log what you harvest so the app knows when to remind you again.")
            return [Nudge(
                kind: .harvest,
                dedupeKey: "harvest",
                cooldownDays: 3,
                priority: 60,
                fireDate: at(today, settings.deliveryMinute),
                title: "Harvest check: \(names)",
                body: ready.count == 1
                    ? "The \(ready[0].name) should have something ready. It's ready when \(ready[0].crop.care.readyWhen)."
                    : "Look over the \(names) for anything ready to pick. Morning picking keeps it crisp.",
                detail: detail.joined(separator: "\n\n"),
                plantIDs: ready.map { $0.id },
                log: SuggestedLog(kind: .harvest, what: "Harvested \(names)", plantIDs: ready.map { $0.id })
            )]
        }

        let first = soon.min { $0.days < $1.days }!
        let names = NudgeText.list(soon.map { $0.plant.name })
        let when = first.days == 1 ? "a day" : "about \(first.days) days"
        return [Nudge(
            kind: .harvest,
            dedupeKey: "harvest_soon",
            cooldownDays: 7,
            priority: 35,
            fireDate: at(today, settings.deliveryMinute),
            title: "Harvest coming: \(names)",
            body: "The \(first.plant.name) should be ready in \(when). Start checking: it's ready when \(first.plant.crop.care.readyWhen).",
            detail: (soon.map { line($0.plant) } + ["These dates are typical for the crop; weather and variety can shift them a week or two either way."])
                .joined(separator: "\n\n"),
            plantIDs: soon.map { $0.plant.id }
        )]
    }

    /// A weekly five-minute look for the pests each crop tends to get, in warm weather.
    func pestCheck(_ state: GardenState, today: LocalDay) -> [Nudge] {
        guard let weather = state.weather else { return [] }
        let highs = weather.days(from: today.adding(days: -3, calendar: calendar), through: today).compactMap { $0.highF }
        guard !highs.isEmpty, highs.reduce(0, +) / Double(highs.count) >= 65 else { return [] }

        let watch = state.plants.filter { plant in
            guard plant.stage.isActive || plant.stage == .mature, plant.crop.care.watchFor != nil else { return false }
            let bedName = state.bedName(for: plant)
            return !state.journal.contains {
                $0.kind == .pestOrDisease && $0.day.days(to: today, calendar: calendar) < 7 && $0.applies(to: plant, bedName: bedName)
            }
        }
        guard !watch.isEmpty else { return [] }

        // One line per crop, and a different crop leads each week so it doesn't read the same.
        var seen: Set<String> = []
        let byCrop = watch.filter { seen.insert($0.crop.id).inserted }
        let week = Int(today.startDate(in: calendar).timeIntervalSince1970 / (7 * 86_400))
        let lead = byCrop[((week % byCrop.count) + byCrop.count) % byCrop.count]
        let options = Toolbox.ranked(for: .pests, inventory: state.inventory)
        let lines = byCrop.map { "\($0.name): \($0.crop.care.watchFor ?? "")." }

        return [Nudge(
            kind: .pestCheck,
            dedupeKey: "pest_check",
            cooldownDays: 7,
            priority: 35,
            fireDate: at(today, settings.deliveryMinute),
            title: "Five-minute pest check",
            body: "Look under the leaves of the \(lead.name) for \(lead.crop.care.watchFor ?? "pests"). Catching them early is half the battle.",
            detail: NudgeText.optionsDetail(
                intro: (["What to look for:"] + lines).joined(separator: "\n"),
                options: options,
                outro: "Start with the gentlest fix. Spray only in the evening, when bees aren't out, and only the plants that need it."
            ),
            plantIDs: watch.map { $0.id },
            log: SuggestedLog(kind: .pestOrDisease, what: "Checked for pests", plantIDs: watch.map { $0.id })
        )]
    }

    /// Suckering, pinching and deadheading for the crops that benefit.
    func pruning(_ state: GardenState, today: LocalDay) -> [Nudge] {
        let due = state.plants.filter { plant in
            let care = plant.crop.care
            guard let every = care.pruneEveryDays, care.prune != nil,
                  [.vegetative, .flowering, .fruiting, .mature].contains(plant.stage) else { return false }
            if let planted = plant.plantedOn, planted.days(to: today, calendar: calendar) < 21 { return false }
            let bedName = state.bedName(for: plant)
            let last = state.journal
                .filter { $0.kind == .pruning && $0.applies(to: plant, bedName: bedName) }
                .map { $0.day }
                .max()
            if let last = last, last.days(to: today, calendar: calendar) < every { return false }
            return true
        }
        guard let first = due.first else { return [] }
        var seen: Set<String> = []
        let lines = due.filter { seen.insert($0.crop.id).inserted }.map { "\($0.name): \($0.crop.care.prune ?? "")" }
        let names = NudgeText.list(due.map { $0.name })
        return [Nudge(
            kind: .pruning,
            dedupeKey: "pruning",
            cooldownDays: 5,
            priority: 30,
            fireDate: at(today, settings.deliveryMinute),
            title: "A little pruning: \(names)",
            body: "\(first.name): \(first.crop.care.prune ?? "")",
            detail: (lines + ["Use clean, sharp snips or your fingers, on a dry day so the cuts heal fast."]).joined(separator: "\n\n"),
            plantIDs: due.map { $0.id },
            log: SuggestedLog(kind: .pruning, what: "Pruned \(names)", plantIDs: due.map { $0.id })
        )]
    }

    /// Quick crops sown a little at a time give a steady harvest instead of one glut.
    func succession(_ state: GardenState, today: LocalDay) -> [Nudge] {
        var due: [(crop: CropProfile, plants: [PlantInfo], since: Int)] = []
        var seen: Set<String> = []
        for plant in state.plants where !seen.contains(plant.crop.id) {
            let crop = plant.crop
            seen.insert(crop.id)
            guard let every = crop.care.sowAgainDays else { continue }
            let same = state.plants.filter { $0.crop.id == crop.id }
            let logged = state.journal
                .filter { entry in entry.kind == .planting && same.contains { entry.applies(to: $0, bedName: state.bedName(for: $0)) } }
                .map { $0.day }
            guard let latest = (same.compactMap { $0.plantedOn } + logged).max() else { continue }
            let since = latest.days(to: today, calendar: calendar)
            // Remind for a few weeks after it's due, then let it go.
            guard since >= every, since <= every + 28 else { continue }

            // Enough season left for it to mature?
            if let fall = state.firstFallFrost, let days = crop.care.firstHarvestDays {
                let thisFall = LocalDay(year: today.year, month: fall.month, day: fall.day)
                let limit = crop.frostTender ? thisFall : thisFall.adding(days: 21, calendar: calendar)
                if thisFall >= today, today.adding(days: days, calendar: calendar) > limit { continue }
            }
            if crop.frostTender, let spring = state.lastSpringFrost {
                let thisSpring = LocalDay(year: today.year, month: spring.month, day: spring.day)
                if today < thisSpring { continue }
            }
            // Cool-season crops bolt in heat; warm-season ones sulk in cold soil.
            if let weather = state.weather {
                let highs = weather.days(from: today, through: today.adding(days: 6, calendar: calendar)).compactMap { $0.highF }
                if !highs.isEmpty {
                    let average = highs.reduce(0, +) / Double(highs.count)
                    if !crop.frostTender && average >= 85 { continue }
                    if crop.frostTender && average < 60 { continue }
                }
            }
            due.append((crop, same, since))
        }
        guard let first = due.first else { return [] }

        let names = NudgeText.list(due.map { $0.crop.name.lowercased() })
        let lines = due.map { item -> String in
            var text = "\(item.crop.name): sow a short row every \(item.crop.care.sowAgainDays ?? 14) days"
            if let days = item.crop.care.firstHarvestDays { text += "; ready in about \(days) days" }
            return text + "."
        }
        let plantIDs = due.flatMap { $0.plants.map { $0.id } }
        return [Nudge(
            kind: .succession,
            dedupeKey: "succession",
            cooldownDays: 7,
            priority: 30,
            fireDate: at(today, settings.deliveryMinute),
            title: "Time to sow more \(names)",
            body: "It's been \(first.since) days since the last \(first.crop.name.lowercased()) went in. A short row now keeps the harvest coming without a glut.",
            detail: (lines + ["A few feet of row at a time is plenty. In summer, sow cool-season crops where they get afternoon shade."])
                .joined(separator: "\n\n"),
            plantIDs: plantIDs,
            log: SuggestedLog(kind: .planting, what: "Sowed more \(names)", plantIDs: plantIDs)
        )]
    }

    /// Once a year, as the first fall frost nears: what to pick, pull, protect and plant.
    func seasonEnd(_ state: GardenState, today: LocalDay) -> [Nudge] {
        guard !state.plants.isEmpty else { return [] }
        var frostDay: LocalDay?
        if let fall = state.firstFallFrost {
            let thisFall = LocalDay(year: today.year, month: fall.month, day: fall.day)
            let gap = today.days(to: thisFall, calendar: calendar)
            if gap <= 21 && gap >= -7 { frostDay = thisFall }
        }
        if frostDay == nil, today.month >= 8, let weather = state.weather {
            frostDay = weather.days(from: today, through: today.adding(days: 10, calendar: calendar))
                .first { ($0.lowF ?? 99) <= 36 }?.day
        }
        guard let frost = frostDay else { return [] }

        let tender = state.plants.filter { $0.crop.frostTender && ($0.stage.isActive || $0.stage == .mature) }
        var tasks: [String] = []
        let bearing = tender.filter { $0.crop.fruiting || $0.crop.id == "basil" }
        if !bearing.isEmpty {
            tasks.append("Pick everything ripe or close to it on the \(NudgeText.list(bearing.map { $0.name })) before the frost. Tomatoes showing any color will finish ripening on the counter.")
        }
        if state.plants.contains(where: { $0.cropID == "sweet_potato" }) {
            tasks.append("Dig the sweet potatoes before frost touches the vines, and cure them somewhere warm for a week.")
        }
        if state.plants.contains(where: { $0.cropID == "citrus" }) {
            tasks.append("Bring potted citrus somewhere protected when nights drop near freezing.")
        }
        tasks.append("Pull plants that are finished and compost the healthy ones; bag anything diseased instead.")
        tasks.append("Cover bare soil with 2 to 3 inches of shredded leaves, or sow a cover crop like cereal rye in the next couple of weeks.")
        if !state.plants.contains(where: { $0.cropID == "garlic" }) {
            tasks.append("Plant garlic two to four weeks after the first frost, for a harvest next summer.")
        }
        tasks.append("Drain and coil hoses before the first hard freeze.")

        let gap = today.days(to: frost, calendar: calendar)
        let title = gap > 0
            ? "First frost around \(frost.spokenName(relativeTo: today, calendar: calendar)): time to wrap up"
            : "Frost season is here: time to wrap up"
        return [Nudge(
            kind: .seasonEnd,
            dedupeKey: "season_end:\(frost.year)",
            cooldownDays: 0,
            priority: 40,
            fireDate: at(today, settings.deliveryMinute),
            title: title,
            body: tasks[0],
            detail: tasks.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n"),
            plantIDs: tender.map { $0.id },
            log: SuggestedLog(kind: .other, what: "Started the fall cleanup")
        )]
    }
}
