import Foundation

/// Turns the garden, its journal and the forecast into timely nudges, then paces them.
/// Rules are deliberately simple and explainable; the coach words them in David's voice.
public struct NudgeEngine {
    public var settings: NudgeSettings
    public var calendar: Calendar

    public init(settings: NudgeSettings = .standard, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Candidates plus pacing in one call.
    public func plan(_ state: GardenState, history: [NudgeHistory], now: Date, horizonDays: Int = 7) -> [Nudge] {
        schedule(candidates(state, now: now), history: history, now: now, horizonDays: horizonDays)
    }

    public func waterStates(_ state: GardenState, today: LocalDay) -> [UUID: WaterState] {
        var result: [UUID: WaterState] = [:]
        for bed in state.beds {
            result[bed.id] = WaterModel.state(
                bed: bed, plants: state.plants(in: bed), journal: state.journal, weather: state.weather,
                today: today, calendar: calendar
            )
        }
        return result
    }

    // MARK: - Candidates

    public func candidates(_ state: GardenState, now: Date) -> [Nudge] {
        guard settings.enabled else { return [] }
        let today = LocalDay(now, calendar: calendar)
        var out: [Nudge] = []
        out += frost(state, today: today)
        let heat = heatStress(state, today: today, now: now)
        out += heat
        if heat.isEmpty { out += drySpell(state, today: today) }
        out += moisture(state, today: today)
        out += wind(state, today: today, now: now)
        out += staking(state, today: today)
        out += foliar(state, today: today, now: now)
        out += feeding(state, today: today)
        out += harvest(state, today: today)
        out += pestCheck(state, today: today)
        out += pruning(state, today: today)
        out += succession(state, today: today)
        out += seasonEnd(state, today: today)
        return out
    }

    func at(_ day: LocalDay, _ minute: Int) -> Date {
        day.date(atMinute: minute, in: calendar)
    }

    func forecastDay(_ state: GardenState, _ day: LocalDay) -> DailyWeather? {
        state.weather?.day(day)
    }

    func frost(_ state: GardenState, today: LocalDay) -> [Nudge] {
        let tender = state.plants.filter { $0.crop.frostTender && ($0.stage.isActive || $0.stage == .mature) }
        guard !tender.isEmpty else { return [] }
        // A day's low usually comes around dawn, so warn the afternoon before.
        for offset in 1...2 {
            let day = today.adding(days: offset, calendar: calendar)
            guard let w = forecastDay(state, day), let low = w.lowF, low <= settings.frostThresholdF else { continue }
            let eve = day.adding(days: -1, calendar: calendar)
            let when = offset == 1 ? "tonight" : "\(eve.spokenName(relativeTo: today, calendar: calendar)) night"
            let names = NudgeText.list(tender.map { $0.name })
            let cover = Toolbox.ranked(for: .frostCover, inventory: state.inventory)
            let first = cover.first
            let bearing = tender.contains { $0.stage == .fruiting || $0.stage == .mature }
            let pickFirst = bearing ? "Pick anything ripe or close to it, then cover" : "Cover"
            return [Nudge(
                kind: .frost,
                dedupeKey: "frost:\(day.string)",
                cooldownDays: 0,
                priority: 100,
                fireDate: at(eve, 16 * 60),
                expires: at(eve, 22 * 60),
                title: "Frost likely \(when) (\(NudgeText.temp(low)))",
                body: "\(pickFirst) the \(names) before dark, all the way to the ground. Water the soil this afternoon; moist soil holds heat.",
                detail: NudgeText.optionsDetail(
                    intro: "The forecast low is \(NudgeText.temp(low)), cold enough to damage the \(names).",
                    options: cover,
                    outro: "Take covers off in the morning once it's above freezing so plants don't overheat."
                ),
                plantIDs: tender.map { $0.id },
                log: SuggestedLog(kind: .other, what: "Covered plants for frost (\(first?.name ?? "covers"))", plantIDs: tender.map { $0.id })
            )]
        }
        return []
    }

    func heatStress(_ state: GardenState, today: LocalDay, now: Date) -> [Nudge] {
        guard state.weather != nil else { return [] }
        let afternoon = calendar.minuteOfDay(now) >= 12 * 60
        let startOffset = afternoon ? 1 : 0
        for offset in startOffset...3 {
            let day = today.adding(days: offset, calendar: calendar)
            guard let w = forecastDay(state, day), let high = w.highF, high >= settings.heatThresholdF else { continue }
            var peak = high
            var length = 1
            var next = day.adding(days: 1, calendar: calendar)
            while let nw = forecastDay(state, next), let nh = nw.highF, nh >= settings.heatThresholdF, length < 7 {
                peak = max(peak, nh)
                length += 1
                next = next.adding(days: 1, calendar: calendar)
            }
            let beds = state.beds.filter { !state.plants(in: $0).isEmpty }
            let bedText = beds.isEmpty || beds.count > 3 ? "your beds" : NudgeText.list(beds.map { $0.name })
            let hasContainers = beds.contains { $0.kind == .container }
            let dayName = day.spokenName(relativeTo: today, calendar: calendar)
            let title = length > 1 ? "Heat wave from \(dayName): up to \(NudgeText.temp(peak))" : "Hot \(dayName): \(NudgeText.temp(peak))"
            let whenToWater = offset == 0 ? "this morning" : "the evening before or early that morning"
            var body = "Deep-water \(bedText) \(whenToWater), top up mulch to 2–3 inches, and hold off on feeding until it cools."
            if hasContainers { body += " Check containers twice a day." }
            let fireDay = offset == 0 ? today : day.adding(days: -1, calendar: calendar)
            return [Nudge(
                kind: .heatStress,
                dedupeKey: "heat_stress",
                cooldownDays: 3,
                priority: 90,
                fireDate: at(fireDay, settings.deliveryMinute),
                expires: at(day, 12 * 60),
                title: title,
                body: body,
                detail: "Highs of \(NudgeText.temp(peak)) stress plants fast: leaves wilt in the afternoon, flowers drop, and tomatoes stop setting fruit above about 90°F. " +
                    "A deep soak (about an inch, slowly) before the heat fills the root zone. Mulch keeps the soil cooler and slows evaporation. " +
                    "Afternoon wilting that recovers by evening is normal; wilting in the morning means water now. Feeding during heat stress can burn roots, so wait until it breaks.",
                bedIDs: beds.map { $0.id },
                log: SuggestedLog(kind: .watering, what: "Deep watering before the heat", bedIDs: beds.map { $0.id }, waterInches: WaterAmount.deep)
            )]
        }
        return []
    }

    func drySpell(_ state: GardenState, today: LocalDay) -> [Nudge] {
        guard let weather = state.weather else { return [] }
        let beds = state.beds.filter { !state.plants(in: $0).isEmpty }
        guard !beds.isEmpty else { return [] }
        let past = weather.days(from: today.adding(days: -7, calendar: calendar), through: today.adding(days: -1, calendar: calendar))
        let ahead = weather.days(from: today, through: today.adding(days: 4, calendar: calendar))
        guard past.count >= 5, ahead.count >= 3 else { return [] }
        let pastRain = past.compactMap { $0.rainInches }.reduce(0, +)
        let pastET = past.compactMap { $0.et0Inches }.reduce(0, +)
        let aheadRain = ahead.compactMap { $0.rainInches }.reduce(0, +)
        guard pastRain < 0.25, aheadRain < 0.2, pastET >= 0.9 else { return [] }
        let bedText = beds.count > 3 ? "your beds" : NudgeText.list(beds.map { $0.name })
        return [Nudge(
            kind: .drySpell,
            dedupeKey: "dry_spell",
            cooldownDays: 5,
            priority: 70,
            fireDate: at(today, settings.deliveryMinute),
            title: "Dry spell: \(NudgeText.inches(pastRain)) of rain this week",
            body: "Almost no rain coming either. Give \(bedText) a slow, deep soak, about an inch, so water reaches 6 inches down.",
            detail: "Plants used about \(NudgeText.inches(pastET)) of water this past week from evaporation and growth, and only \(NudgeText.inches(pastRain)) of rain fell. " +
                "One deep soak beats several sprinkles: it sends roots down where the soil stays cool. Water early in the morning, slowly, and check with a finger 2 inches down an hour later.",
            bedIDs: beds.map { $0.id },
            log: SuggestedLog(kind: .watering, what: "Deep soak in a dry spell", bedIDs: beds.map { $0.id }, waterInches: WaterAmount.deep)
        )]
    }

    func moisture(_ state: GardenState, today: LocalDay) -> [Nudge] {
        guard state.weather != nil else { return [] }
        let states = waterStates(state, today: today)
        var waterBeds: [LocalDay: [(BedInfo, WaterState)]] = [:]
        var checkBeds: [LocalDay: [(BedInfo, WaterState)]] = [:]

        for bed in state.beds {
            let plants = state.plants(in: bed).filter { $0.stage.isActive || $0.stage == .mature }
            guard !plants.isEmpty, let ws = states[bed.id], ws.status != .unknown else { continue }
            let touchedToday = state.journal.contains {
                $0.day == today && ($0.kind == .watering || $0.kind == .moistureCheck) && $0.applies(to: bed)
            }
            if touchedToday { continue }
            switch ws.status {
            case .dry:
                waterBeds[today, default: []].append((bed, ws))
                continue
            case .check:
                if !rainComing(state, today: today) { checkBeds[today, default: []].append((bed, ws)) }
                continue
            case .ok, .unknown:
                break
            }
            // Look ahead: when will it get there if nothing changes?
            for p in ws.projected where p.day > today && p.day <= today.adding(days: 3, calendar: calendar) {
                if p.status == .dry {
                    waterBeds[p.day, default: []].append((bed, ws))
                    break
                }
                if p.status == .check {
                    checkBeds[p.day, default: []].append((bed, ws))
                    break
                }
            }
        }

        var out: [Nudge] = []
        if let day = waterBeds.keys.min(), let list = waterBeds[day] {
            let names = NudgeText.list(list.map { $0.0.name })
            let first = list[0].1
            let used = NudgeText.inches(min(first.deficitInches + 0.0001, first.capacityInches))
            out.append(Nudge(
                kind: .waterNow,
                dedupeKey: "water_now",
                cooldownDays: 1,
                priority: 80,
                fireDate: at(day, settings.deliveryMinute),
                title: list.count == 1 ? "\(list[0].0.name) is probably dry" : "Beds are probably dry",
                body: "\(names) \(list.count == 1 ? "has" : "have") likely used most of the soil's water. Water slowly until it soaks in about an inch, ideally this morning.",
                detail: "From rain, evaporation and your watering log, \(list[0].0.name) has used about \(used) of the \(NudgeText.inches(first.capacityInches)) its soil holds. " +
                    "Do a quick finger test first if you like: dry 2 inches down means water now. Log it afterward so the estimate stays accurate.",
                bedIDs: list.map { $0.0.id },
                log: SuggestedLog(kind: .watering, what: "Deep watering", bedIDs: list.map { $0.0.id }, waterInches: WaterAmount.deep)
            ))
        }
        let waterDay = waterBeds.keys.min()
        if let day = checkBeds.keys.min(), day != waterDay, let list = checkBeds[day] {
            let names = NudgeText.list(list.map { $0.0.name })
            out.append(Nudge(
                kind: .moistureCheck,
                dedupeKey: "moisture_check",
                cooldownDays: 1,
                priority: 60,
                fireDate: at(day, settings.deliveryMinute),
                title: "Finger test: \(names)",
                body: "Push a finger 2 inches into the soil. Dry? Water deeply. Cool and damp? Wait a day. Log what you find.",
                detail: "There are no soil sensors, so your finger is the sensor. Logging dry, slightly moist, moist or wet resets the app's water estimate for the bed and makes the next nudge more accurate.",
                bedIDs: list.map { $0.0.id },
                log: SuggestedLog(kind: .moistureCheck, what: "Finger test", bedIDs: list.map { $0.0.id })
            ))
        }
        return out
    }

    private func rainComing(_ state: GardenState, today: LocalDay) -> Bool {
        for offset in 0...1 {
            guard let w = forecastDay(state, today.adding(days: offset, calendar: calendar)) else { continue }
            if (w.rainInches ?? 0) >= 0.4 && (w.rainChance ?? 100) >= 60 { return true }
        }
        return false
    }

    func wind(_ state: GardenState, today: LocalDay, now: Date) -> [Nudge] {
        let tall = state.plants.filter {
            $0.crop.needsSupport && ($0.stage == .vegetative || $0.stage == .flowering || $0.stage == .fruiting || $0.stage == .mature)
        }
        guard !tall.isEmpty else { return [] }
        for offset in 0...2 {
            let day = today.adding(days: offset, calendar: calendar)
            guard let w = forecastDay(state, day), let gust = w.windForStakes, gust >= settings.windThresholdMph else { continue }
            if offset == 0 && calendar.minuteOfDay(now) >= 12 * 60 { continue }
            let fireDay = offset == 0 ? today : day.adding(days: -1, calendar: calendar)
            let names = NudgeText.list(tall.map { $0.name })
            let dayName = day.spokenName(relativeTo: today, calendar: calendar)
            return [Nudge(
                kind: .wind,
                dedupeKey: "wind",
                cooldownDays: 2,
                priority: 65,
                fireDate: at(fireDay, settings.deliveryMinute),
                expires: at(day, 12 * 60),
                title: "Windy \(dayName): gusts near \(Int(gust.rounded())) mph",
                body: "Check stakes, cages and ties on the \(names) before then. Loosen tight ties and add one under heavy branches.",
                detail: "Wind snaps stems at tight ties and rocks loose stakes. Tie in a loose figure eight, and push stakes a few inches deeper if they wobble.",
                plantIDs: tall.map { $0.id },
                log: SuggestedLog(kind: .staking, what: "Checked stakes and ties before wind", plantIDs: tall.map { $0.id })
            )]
        }
        return []
    }

    func staking(_ state: GardenState, today: LocalDay) -> [Nudge] {
        let due = state.plants.filter { plant in
            let crop = plant.crop
            guard crop.needsSupport, !plant.staked, plant.stage.isActive else { return false }
            if let planted = plant.plantedOn {
                return planted.days(to: today, calendar: calendar) >= crop.stakeByDays
            }
            return plant.stage != .seedling
        }
        guard !due.isEmpty else { return [] }
        let names = NudgeText.list(due.map { $0.name })
        let maxDays = due.compactMap { $0.plantedOn?.days(to: today, calendar: calendar) }.max()
        let since = maxDays.map { "They've been in \($0) days without support. " } ?? ""
        return [Nudge(
            kind: .staking,
            dedupeKey: "staking",
            cooldownDays: 4,
            priority: 50,
            fireDate: at(today, settings.deliveryMinute),
            title: "Time to stake the \(names)",
            body: "\(since)Set stakes or cages now, 3–4 inches from the stem, before roots spread. Tie loosely in a figure eight.",
            detail: "Staking early avoids tearing roots later and keeps fruit off the soil, which cuts disease. Cages suit bushy plants; a single stake plus pruning suits tall indeterminate tomatoes. Mark them staked in the app so this stops.",
            plantIDs: due.map { $0.id },
            log: SuggestedLog(kind: .staking, what: "Staked", plantIDs: due.map { $0.id })
        )]
    }

    func foliar(_ state: GardenState, today: LocalDay, now: Date) -> [Nudge] {
        let plants = state.plants.filter { plant in
            guard plant.crop.foliarBenefit,
                  plant.stage == .vegetative || plant.stage == .flowering || plant.stage == .fruiting else { return false }
            if let planted = plant.plantedOn, planted.days(to: today, calendar: calendar) < 14 { return false }
            return true
        }
        guard !plants.isEmpty, let weather = state.weather, !weather.hours.isEmpty else { return [] }

        let lastSpray = state.journal
            .filter { entry in entry.kind == .foliarSpray && plants.contains { entry.applies(to: $0, bedName: state.bedName(for: $0)) } }
            .map { $0.day }
            .max()
        if let last = lastSpray, last.days(to: today, calendar: calendar) < settings.foliarIntervalDays { return [] }

        guard let window = bestFoliarWindow(weather.hours, after: now.addingTimeInterval(3600), today: today) else { return [] }
        let windowDay = LocalDay(window.start, calendar: calendar)
        let isMorning = calendar.minuteOfDay(window.start) < 12 * 60
        var fire: Date
        if isMorning {
            fire = at(windowDay.adding(days: -1, calendar: calendar), 18 * 60 + 30)
        } else {
            fire = at(windowDay, 15 * 60)
        }
        if fire <= now { fire = window.start.addingTimeInterval(-45 * 60) }

        let options = Toolbox.ranked(for: .foliar, inventory: state.inventory)
        let pick = options.first
        let product = pick.map { $0.tier == .owned ? "your \($0.name)" : $0.name.lowercased() } ?? "liquid kelp"
        let names = NudgeText.list(plants.map { $0.name })
        let dayName = windowDay.spokenName(relativeTo: today, calendar: calendar)
        let temp = window.tempF.map { "\(NudgeText.temp($0)), " } ?? ""
        return [Nudge(
            kind: .foliar,
            dedupeKey: "foliar",
            cooldownDays: 3,
            priority: 25,
            fireDate: fire,
            expires: window.end,
            title: "Foliar window \(dayName) \(NudgeText.hourRange(window.start, window.end, calendar: calendar))",
            body: "\(temp)calm and dry. Spray the \(names) with \(product), coating leaf undersides until just dripping.",
            detail: NudgeText.optionsDetail(
                intro: "Foliar feeding works best when it's cool, still and dry, so leaves stay wet long enough to absorb it without burning. " +
                    (lastSpray.map { "Last spray: \($0.spokenName(relativeTo: today, calendar: calendar))." } ?? "No foliar spray logged yet."),
                options: options,
                outro: "Every 1 to 2 weeks during active growth is plenty. It's a boost, not a replacement for feeding the soil."
            ),
            plantIDs: plants.map { $0.id },
            log: SuggestedLog(kind: .foliarSpray, what: pick?.name ?? "Foliar spray", plantIDs: plants.map { $0.id })
        )]
    }

    struct Window {
        var start: Date
        var end: Date
        var tempF: Double?
    }

    /// Earliest morning (6–9 AM) or evening (6–8 PM) window that is cool, calm and dry.
    func bestFoliarWindow(_ hours: [HourlyWeather], after earliest: Date, today: LocalDay) -> Window? {
        let slots: [(startMinute: Int, length: Int)] = [(6 * 60, 3), (18 * 60, 2)]
        for offset in 0...2 {
            let day = today.adding(days: offset, calendar: calendar)
            for slot in slots {
                let start = at(day, slot.startMinute)
                let end = start.addingTimeInterval(Double(slot.length) * 3600)
                guard start >= earliest else { continue }
                let inWindow = hours.filter { $0.time >= start && $0.time < end }
                guard inWindow.count >= slot.length else { continue }
                let after = hours.filter { $0.time >= end && $0.time < end.addingTimeInterval(4 * 3600) }
                let ok = inWindow.allSatisfy { h in
                    guard let t = h.tempF, let wind = h.windMph else { return false }
                    return t >= 45 && t <= 85 && wind <= 10 && (h.rainChance ?? 0) <= 30
                } && after.allSatisfy { ($0.rainChance ?? 0) <= 40 }
                if ok {
                    let temps = inWindow.compactMap { $0.tempF }
                    let avg = temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
                    return Window(start: start, end: end, tempF: avg)
                }
            }
        }
        return nil
    }

    func feeding(_ state: GardenState, today: LocalDay) -> [Nudge] {
        var firstFeed: [PlantInfo] = []
        var due: [(PlantInfo, Int?)] = []
        var sideDress: [PlantInfo] = []

        for plant in state.plants where plant.stage.isActive {
            let crop = plant.crop
            let bedName = state.bedName(for: plant)
            let feeds = state.journal.filter { $0.kind.countsAsFeeding && $0.applies(to: plant, bedName: bedName) }
            let lastFeed = feeds.map { $0.day }.max()
            let daysSincePlanting = plant.plantedOn?.days(to: today, calendar: calendar)

            // Only heavy feeders get a first feed, a few weeks in once the planting-hole compost is used up.
            if let planted = plant.plantedOn, let d = daysSincePlanting, d >= 14, d <= 35, crop.feeding == .heavy {
                let fedSince = feeds.contains { $0.day >= planted.adding(days: -7, calendar: calendar) }
                if !fedSince { firstFeed.append(plant); continue }
            }

            var interval = crop.feeding.feedIntervalDays
            // Fruiting crops get a side-dressing when they flower; light feeders (beans, peas) don't need it.
            let flowering = crop.fruiting && plant.stage == .flowering && crop.feeding != .light
            if flowering { interval = crop.feeding == .heavy ? 14 : 21 }
            guard let every = interval, plant.stage != .seedling else { continue }
            guard let reference = lastFeed ?? plant.plantedOn else { continue }
            let since = reference.days(to: today, calendar: calendar)
            if since >= every {
                if flowering { sideDress.append(plant) } else { due.append((plant, lastFeed == nil ? nil : since)) }
            }
        }

        // Don't feed into a heat wave: wait until it breaks (at most three days).
        var fireDay = today
        var heatNote = ""
        for offset in 0...3 {
            let d = today.adding(days: offset, calendar: calendar)
            if let high = forecastDay(state, d)?.highF, high >= 95 {
                fireDay = d.adding(days: 1, calendar: calendar)
                heatNote = " Wait until the heat breaks."
            } else {
                break
            }
        }

        var out: [Nudge] = []
        func make(_ kind: NudgeKind, _ plants: [PlantInfo], key: String, priority: Int, title: String, lead: String) {
            let options = Toolbox.ranked(for: .feed, inventory: state.inventory)
            guard let pick = options.first else { return }
            let use = pick.tier == .owned ? "your \(pick.name)" : pick.name.lowercased()
            let body = "\(lead) Use \(use): \(NudgeText.lowerFirst(pick.howTo))\(heatNote)"
            out.append(Nudge(
                kind: kind,
                dedupeKey: key,
                cooldownDays: kind == .firstFeed ? 4 : 3,
                priority: priority,
                fireDate: at(fireDay, settings.deliveryMinute),
                title: title,
                body: body,
                detail: NudgeText.optionsDetail(
                    intro: "Heavy feeders and fruiting crops use up soil nitrogen as they grow; a side-dressing now and then keeps them steady. More than that gives lush, soft growth that invites aphids and sets less fruit. The app checks your journal so it won't nag about plants you've fed recently.",
                    options: options,
                    outro: ""
                ),
                plantIDs: plants.map { $0.id },
                log: SuggestedLog(kind: .feeding, what: pick.name, plantIDs: plants.map { $0.id })
            ))
        }

        if !firstFeed.isEmpty {
            let names = NudgeText.list(firstFeed.map { $0.name })
            make(.firstFeed, firstFeed, key: "first_feed", priority: 55, title: "First feed for the \(names)",
                 lead: "They're settled in and ready for their first meal.")
        }
        if !sideDress.isEmpty {
            let names = NudgeText.list(sideDress.map { $0.name })
            make(.feed, sideDress, key: "side_dress", priority: 50, title: "Flowers on the \(names): side-dress now",
                 lead: "First flowers are the signal to feed fruiting crops.")
        }
        if !due.isEmpty {
            let names = NudgeText.list(due.map { $0.0.name })
            let days = due.compactMap { $0.1 }.max()
            let lead = days.map { "Last feed was \($0) days ago." } ?? "No feeding logged since planting."
            make(.feed, due.map { $0.0 }, key: "feed", priority: 45, title: "The \(names) are due for a feed", lead: lead)
        }
        return out
    }

    // MARK: - Pacing

    /// Applies cooldowns, snoozes, quiet hours, a daily cap and spacing. Highest priority wins.
    public func schedule(_ candidates: [Nudge], history: [NudgeHistory], now: Date, horizonDays: Int = 7) -> [Nudge] {
        guard settings.enabled else { return [] }
        let horizonEnd = now.addingTimeInterval(Double(horizonDays) * 86_400)
        let spacing = Double(max(0, settings.minimumSpacingMinutes)) * 60
        var latestByKey: [String: NudgeHistory] = [:]
        for h in history {
            if let existing = latestByKey[h.dedupeKey], existing.date >= h.date { continue }
            latestByKey[h.dedupeKey] = h
        }

        let ordered = candidates.enumerated().sorted { a, b in
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            if a.element.fireDate != b.element.fireDate { return a.element.fireDate < b.element.fireDate }
            return a.offset < b.offset
        }.map { $0.element }

        var usedKeys: Set<String> = []
        var perDay: [LocalDay: [Date]] = [:]
        var result: [Nudge] = []

        for candidate in ordered {
            var n = candidate
            guard !usedKeys.contains(n.dedupeKey) else { continue }

            if let h = latestByKey[n.dedupeKey] {
                if let until = h.snoozedUntil {
                    // Snoozed: bring it back when the snooze ends.
                    if until > n.fireDate { n.fireDate = until }
                } else {
                    // Delivered or done: wait out the cooldown (an hour early is fine, so a daily
                    // reminder can keep its usual time). Cooldown 0 means never repeat this key.
                    if n.cooldownDays == 0 { continue }
                    let allowed = h.date.addingTimeInterval(Double(n.cooldownDays) * 86_400 - 3_600)
                    if n.fireDate < allowed { n.fireDate = allowed }
                }
            }

            if n.fireDate < now.addingTimeInterval(60) { n.fireDate = now.addingTimeInterval(60) }
            n.fireDate = outOfQuietHours(n.fireDate)

            var day = LocalDay(n.fireDate, calendar: calendar)
            var times = perDay[day] ?? []
            var guardCount = 0
            while times.contains(where: { abs($0.timeIntervalSince(n.fireDate)) < spacing }) && guardCount < 12 {
                n.fireDate = outOfQuietHours(n.fireDate.addingTimeInterval(spacing))
                day = LocalDay(n.fireDate, calendar: calendar)
                times = perDay[day] ?? []
                guardCount += 1
            }

            if let expires = n.expires, n.fireDate > expires { continue }
            if n.fireDate > horizonEnd { continue }
            if times.count >= max(1, settings.maxPerDay) { continue }

            usedKeys.insert(n.dedupeKey)
            perDay[day, default: []].append(n.fireDate)
            result.append(n)
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// Moves a time that falls in quiet hours to the end of quiet hours.
    func outOfQuietHours(_ date: Date) -> Date {
        let minute = calendar.minuteOfDay(date)
        guard settings.isQuiet(minute: minute) else { return date }
        let day = LocalDay(date, calendar: calendar)
        let wraps = settings.quietStartMinute > settings.quietEndMinute
        if wraps && minute >= settings.quietStartMinute {
            return at(day.adding(days: 1, calendar: calendar), settings.quietEndMinute)
        }
        return at(day, settings.quietEndMinute)
    }
}

/// Small text helpers for nudge wording.
public enum NudgeText {
    public static func list(_ names: [String]) -> String {
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0.lowercased()).inserted }
        switch unique.count {
        case 0: return ""
        case 1: return unique[0]
        case 2: return "\(unique[0]) and \(unique[1])"
        case 3: return "\(unique[0]), \(unique[1]) and \(unique[2])"
        default: return "\(unique[0]), \(unique[1]) and \(unique.count - 2) more"
        }
    }

    public static func temp(_ f: Double) -> String { "\(Int(f.rounded()))°F" }

    public static func inches(_ v: Double) -> String {
        if v < 0.05 { return "0 in" }
        return String(format: "%.1f in", v)
    }

    public static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// "6–9 AM" or "6–8 PM".
    public static func hourRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        let a = calendar.component(.hour, from: start)
        let b = calendar.component(.hour, from: end)
        func h12(_ h: Int) -> Int { h % 12 == 0 ? 12 : h % 12 }
        let aPM = a >= 12
        let bPM = b >= 12
        if aPM == bPM { return "\(h12(a))–\(h12(b)) \(bPM ? "PM" : "AM")" }
        return "\(h12(a)) \(aPM ? "PM" : "AM")–\(h12(b)) \(bPM ? "PM" : "AM")"
    }

    /// An explanation followed by numbered options in use-what-you-have order.
    public static func optionsDetail(intro: String, options: [RankedOption], outro: String) -> String {
        var lines: [String] = [intro]
        for (i, o) in options.prefix(4).enumerated() {
            var line = "\(i + 1). \(o.name) (\(o.tier.displayName.lowercased())): \(o.howTo)"
            if !o.price.isEmpty { line += " Typical price: \(o.price)." }
            if !o.caution.isEmpty { line += " Note: \(o.caution)" }
            lines.append(line)
        }
        if !outro.isEmpty { lines.append(outro) }
        return lines.joined(separator: "\n\n")
    }
}
