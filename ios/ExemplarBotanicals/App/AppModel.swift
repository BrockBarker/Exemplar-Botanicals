import Foundation
import SwiftData
import SwiftUI
import BackgroundTasks
import GardenCore

enum AppTab: Hashable {
    case today, coach, diagnose, garden, journal
}

/// App-wide state and the work that ties the pieces together: weather refresh, nudge planning
/// and notifications, the coach, and record keeping. Views read it from the environment.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let refreshTaskID = "com.exemplarbotanicals.refresh"

    let container: ModelContainer
    let config: AppConfig
    let coach: CoachService
    let voice = VoicePlayer()

    var selectedTab: AppTab = .today

    // Weather
    var weather: WeatherReport?
    var weatherMessage: String?
    var isRefreshing = false

    // Nudges
    var ledger: NudgeLedger
    /// Nudge wording in David's voice, keyed by a hash of the draft wording.
    var phrasings: [String: NudgePhrasing]
    /// A nudge to open on the Today tab (set when a notification is tapped).
    var focusedNudgeID: String?

    // Coach
    var health: HealthResponse?
    var healthMessage: String?
    var isSending = false
    var coachError: String?
    /// Where the next chat message comes from, e.g. "Ask David" on a nudge.
    var pendingCoachContext: CoachContext?
    var coachDraft = ""

    /// The garden's time zone (from its location); the phone's until one is known.
    var timeZoneID: String?

    private init() {
        container = Self.makeContainer()
        config = AppConfig.load()
        coach = CoachService(endpoint: config.endpoint)
        weather = Store.load(WeatherReport.self, from: Store.weatherFile)
        ledger = Store.load(NudgeLedger.self, from: Store.ledgerFile) ?? NudgeLedger()
        phrasings = Store.load([String: NudgePhrasing].self, from: Store.phrasingFile) ?? [:]
        timeZoneID = GardenRepository.existingProfile(container.mainContext)?.timeZoneID
        GardenRepository.backfillPhotoDates(container.mainContext)
        GardenRepository.relaxFoliarDefault(container.mainContext)
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(Schema1.models)
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Couldn't open the garden database: \(error)")
        }
    }

    var context: ModelContext { container.mainContext }
    var calendar: Calendar { Calendar.garden(timeZoneID: timeZoneID ?? weather?.timeZoneID) }
    var today: LocalDay { LocalDay(Date(), calendar: calendar) }
    var isDemo: Bool { !coach.isLive }
    var coachName: String { config.coachName }
    /// The backend has David's cloned voice set up.
    var voiceAvailable: Bool { coach.isLive && (health?.voiceAvailable ?? false) }

    func save() {
        do {
            try context.save()
        } catch {
            print("Save failed: \(error)")
        }
    }

    // MARK: - Refresh

    /// Weather, then nudges. Called when the app becomes active and from background refresh.
    func refresh(forceWeather: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshWeather(force: forceWeather)
        await replanNudges()
        if health == nil { await checkHealth() }
    }

    func backgroundRefresh() async {
        Self.scheduleBackgroundRefresh()
        await refresh()
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    func refreshWeather(force: Bool) async {
        let profile = GardenRepository.profile(context)
        guard let lat = profile.latitude, let lon = profile.longitude else { return }
        let sameSpot = weather.map { abs($0.latitude - lat) < 0.1 && abs($0.longitude - lon) < 0.1 } ?? false
        if !force, sameSpot, let w = weather, Date().timeIntervalSince(w.fetchedAt) < 3600 { return }

        // Ask for enough history to cover the gap since the last fetch (up to Open-Meteo's 92 days).
        var pastDays = 92
        if sameSpot, let w = weather {
            pastDays = min(92, max(7, Int(Date().timeIntervalSince(w.fetchedAt) / 86_400) + 3))
        }
        do {
            let fresh = try await WeatherService.fetch(latitude: lat, longitude: lon, pastDays: pastDays)
            let merged = sameSpot ? (weather?.merging(fresh) ?? fresh) : fresh
            weather = merged
            weatherMessage = nil
            Store.save(merged, to: Store.weatherFile)
            if profile.timeZoneID != fresh.timeZoneID {
                profile.timeZoneID = fresh.timeZoneID
                save()
            }
            timeZoneID = fresh.timeZoneID
        } catch {
            weatherMessage = weather == nil
                ? "Couldn't get the weather. Check your connection and pull to refresh."
                : "Couldn't update the weather just now; showing the last forecast."
        }
    }

    func checkHealth() async {
        guard coach.isLive else {
            healthMessage = nil
            return
        }
        do {
            health = try await coach.health()
            healthMessage = nil
        } catch {
            healthMessage = (error as? CoachAPIError)?.userMessage ?? error.localizedDescription
        }
    }

    // MARK: - Nudges

    func replanNudges() async {
        let garden = GardenRepository.load(context)
        guard garden.profile.onboarded else { return }
        let engine = NudgeEngine(settings: garden.profile.nudgeSettings, calendar: calendar)
        let plan = ledger.replan(engine: engine, state: garden.state(weather: weather), now: Date())
        Store.save(ledger, to: Store.ledgerFile)
        await phrase(plan + ledger.inbox(now: Date()))
        await NotificationScheduler.schedule(
            plan, enabled: garden.profile.nudgesEnabled, title: { self.title(for: $0) }, body: { self.body(for: $0) }
        )
    }

    /// Rewords nudges in David's voice (live coach only). Draft wording is used when this fails.
    private func phrase(_ nudges: [Nudge]) async {
        guard coach.isLive else { return }
        var seen: Set<String> = []
        let missing = nudges.filter { phrasings[Self.phraseKey($0)] == nil && seen.insert(Self.phraseKey($0)).inserted }
        if !missing.isEmpty {
            let drafts = missing.prefix(12).map { n in
                NudgeDraft(id: Self.phraseKey(n), kind: n.kind.rawValue, title: n.title, body: n.body)
            }
            if let result = try? await coach.phrase(Array(drafts)) {
                for p in result { phrasings[p.id] = p }
            }
        }
        let keep = Set((ledger.scheduled + ledger.delivered).map { Self.phraseKey($0) })
        phrasings = phrasings.filter { keep.contains($0.key) }
        Store.save(phrasings, to: Store.phrasingFile)
    }

    static func phraseKey(_ nudge: Nudge) -> String {
        Store.stableHash("\(nudge.dedupeKey)|\(nudge.title)|\(nudge.body)")
    }

    func title(for nudge: Nudge) -> String { phrasings[Self.phraseKey(nudge)]?.title ?? nudge.title }
    func body(for nudge: Nudge) -> String { phrasings[Self.phraseKey(nudge)]?.body ?? nudge.body }

    func handleNotification(actionID: String, nudgeID: String) async {
        ledger.settle(now: Date())
        guard let nudge = ledger.nudge(id: nudgeID) else {
            selectedTab = .today
            return
        }
        if actionID == NotificationScheduler.doneAction {
            complete(nudge)
        } else if actionID == NotificationScheduler.snoozeAction {
            snooze(nudge, until: Date().addingTimeInterval(3 * 3600))
        } else if actionID.hasPrefix(NotificationScheduler.moisturePrefix),
                  let reading = MoistureReading(rawValue: String(actionID.dropFirst(NotificationScheduler.moisturePrefix.count))) {
            complete(nudge, moisture: reading)
        } else {
            selectedTab = .today
            focusedNudgeID = nudge.id
        }
    }

    /// The gardener did what the nudge asked: log it in the journal and stop reminding.
    func complete(_ nudge: Nudge, moisture: MoistureReading? = nil) {
        if let log = nudge.log {
            logSuggested(log, moisture: moisture, source: "nudge")
        }
        ledger.markHandled(nudge, now: Date())
        Store.save(ledger, to: Store.ledgerFile)
        Task { await replanNudges() }
    }

    func snooze(_ nudge: Nudge, until: Date) {
        ledger.snooze(nudge, until: until, now: Date())
        Store.save(ledger, to: Store.ledgerFile)
        Task { await replanNudges() }
    }

    func dismiss(_ nudge: Nudge) {
        ledger.markHandled(nudge, now: Date())
        Store.save(ledger, to: Store.ledgerFile)
        Task { await replanNudges() }
    }

    func askCoach(about nudge: Nudge) {
        pendingCoachContext = CoachContext(kind: "nudge", text: "\(title(for: nudge)). \(body(for: nudge))")
        coachDraft = "About this: what should I do?"
        selectedTab = .coach
    }

    /// Writes a nudge's suggested log to the journal: one entry per bed, and per plant when a
    /// nudge covers only some plants in a bed.
    func logSuggested(_ log: SuggestedLog, moisture: MoistureReading? = nil, source: String) {
        let garden = GardenRepository.load(context)
        let day = today
        let bedsByID = Dictionary(garden.beds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var targets: [(bed: Bed?, plant: Plant?)] = log.bedIDs.compactMap { bedsByID[$0] }.map { (bed: $0, plant: nil) }

        let plants = garden.plants.filter { log.plantIDs.contains($0.id) }
        let byBed = Dictionary(grouping: plants) { $0.bedID }
        for (bedID, group) in byBed {
            if let bedID = bedID, let bed = bedsByID[bedID],
               garden.plants.filter({ $0.bedID == bedID }).count == group.count {
                if !targets.contains(where: { $0.bed?.id == bedID }) { targets.append((bed: bed, plant: nil)) }
            } else {
                for plant in group { targets.append((bed: plant.bedID.flatMap { bedsByID[$0] }, plant: plant)) }
            }
        }
        if targets.isEmpty { targets = [(bed: nil, plant: nil)] }

        for target in targets {
            let entry = JournalEntry(day: day, kind: log.kind, what: log.what, source: source)
            entry.bedID = target.bed?.id
            entry.bedName = target.bed?.name ?? ""
            entry.plantID = target.plant?.id
            entry.plantName = target.plant?.name ?? ""
            entry.waterInches = log.waterInches
            entry.moisture = moisture
            if let reading = moisture { entry.what = "Finger test: \(reading.displayName.lowercased())" }
            context.insert(entry)
        }
        save()
    }

    // MARK: - Coach

    func snapshot() -> GardenSnapshot {
        let garden = GardenRepository.load(context)
        let now = Date()
        return GardenSnapshot.make(
            profile: garden.profile.info,
            state: garden.state(weather: weather),
            coachNotes: garden.notes.map { $0.info },
            nudges: ledger.inbox(now: now) + ledger.upcoming(now: now, within: 72),
            now: now,
            calendar: calendar
        )
    }

    /// Sends a message to the coach (or the demo coach), saves the reply and applies any
    /// record updates the coach made.
    func sendToCoach(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        let contextNote = pendingCoachContext
        pendingCoachContext = nil
        coachError = nil

        context.insert(ChatMessage(role: .user, text: trimmed, contextText: contextNote?.text))
        save()
        await replyToLatest(context: contextNote)
    }

    /// Asks again after a failed reply (the gardener's last message is already saved).
    func retryCoach() async {
        coachError = nil
        await replyToLatest(context: nil)
    }

    private func replyToLatest(context contextNote: CoachContext?) async {
        isSending = true
        defer { isSending = false }

        let history = GardenRepository.chatHistory(context)
        guard let last = history.last, last.isUser else { return }

        if !coach.isLive {
            // Remember what they said they have (or ran out of), as the live coach does with
            // update_inventory, then answer with it already counted.
            let noted = SupplyMentions.actions(from: last.text)
            let lines = noted.isEmpty ? [] : ActionApplier.apply(noted, context: context, today: today)
            let garden = GardenRepository.load(context)
            let reply = DemoCoach.reply(
                to: last.text, state: garden.state(weather: weather), profile: garden.profile.info, now: Date(), calendar: calendar,
                noted: noted
            )
            try? await Task.sleep(nanoseconds: 600_000_000)
            context.insert(ChatMessage(role: .assistant, text: reply, actionLines: lines, isDemo: true))
            save()
            return
        }

        let turns = history.filter { !$0.isDemo }.suffix(40).map {
            ChatTurn(role: $0.isUser ? .user : .assistant, text: $0.text)
        }
        do {
            let response = try await coach.chat(CoachRequest(messages: Array(turns), garden: snapshot(), context: contextNote))
            let lines = ActionApplier.apply(response.actions, context: context, today: today)
            context.insert(ChatMessage(role: .assistant, text: response.reply, actionLines: lines))
            save()
            if !response.actions.isEmpty { Task { await replanNudges() } }
            if GardenRepository.profile(context).voiceEnabled, voiceAvailable {
                await voice.play(text: response.reply, service: coach)
            }
        } catch {
            coachError = (error as? CoachAPIError)?.userMessage ?? "Something went wrong. Try again."
        }
    }

    func clearChat() {
        for message in GardenRepository.chatHistory(context) {
            context.delete(message)
        }
        save()
    }

    // MARK: - Setup

    /// Saves the location chosen in onboarding or Settings and fetches its weather.
    func setLocation(label: String, latitude: Double, longitude: Double, timeZoneID zone: String?) async {
        let profile = GardenRepository.profile(context)
        let movedLat = profile.latitude.map { abs($0 - latitude) > 0.1 } ?? true
        let movedLon = profile.longitude.map { abs($0 - longitude) > 0.1 } ?? true
        let moved = movedLat || movedLon
        profile.locationLabel = label
        profile.latitude = latitude
        profile.longitude = longitude
        if let zone = zone {
            profile.timeZoneID = zone
            timeZoneID = zone
        }
        save()
        if moved {
            weather = nil
            Store.remove(Store.weatherFile)
        }
        await refreshWeather(force: true)
    }

    /// Erases everything on this phone and starts over.
    func eraseAll() {
        do {
            try context.delete(model: ChatMessage.self)
            try context.delete(model: CoachNote.self)
            try context.delete(model: InventoryItem.self)
            try context.delete(model: JournalEntry.self)
            try context.delete(model: Plant.self)
            try context.delete(model: Bed.self)
            try context.delete(model: GardenProfile.self)
            try context.save()
        } catch {
            print("Erase failed: \(error)")
        }
        weather = nil
        ledger = NudgeLedger()
        phrasings = [:]
        timeZoneID = nil
        for file in [Store.weatherFile, Store.ledgerFile, Store.phrasingFile] { Store.remove(file) }
        voice.clearCache()
        Task { await NotificationScheduler.schedule([], enabled: false, title: { $0.title }, body: { $0.body }) }
        selectedTab = .today
    }
}
