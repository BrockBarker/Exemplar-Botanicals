import XCTest
@testable import GardenCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SnapshotTests: XCTestCase {
    private func makeSnapshot() -> (GardenSnapshot, BedInfo, PlantInfo) {
        let bed = Fixtures.bed(mulch: "straw")
        let tomato = Fixtures.plant("Big Beef", crop: "tomato", bed: bed, plantedDaysAgo: 20, stage: .flowering, staked: true)
        let lettuce = Fixtures.plant("Butterhead", crop: "lettuce", bed: bed, plantedDaysAgo: 20)
        let journal = [
            JournalInfo(day: Fixtures.day(-3), kind: .feeding, what: "Compost", plantID: tomato.id),
            JournalInfo(day: Fixtures.day(-1), kind: .watering, what: "Deep soak", bedID: bed.id, waterInches: 1),
            JournalInfo(day: Fixtures.day(-90), kind: .planting, what: "Old entry"),
        ]
        let profile = GardenProfileInfo(
            gardenerName: "Sam", locationLabel: "Chicago, IL", latitude: 41.878_113, longitude: -87.629_799,
            timeZoneID: Fixtures.zone, usdaZone: "6a", monthlyBudget: 25, budgetNotes: "", avoidUrine: true
        )
        let state = Fixtures.state(
            beds: [bed], plants: [tomato, lettuce], journal: journal,
            inventory: [InventoryInfo(name: "Alfalfa pellets", category: .fertilizer, quantity: "40 lb")],
            weather: Fixtures.weather(et0: 0.2)
        )
        let nudge = Fixtures.nudge("staking", at: Fixtures.at(0, 7, 30))
        let snapshot = GardenSnapshot.make(
            profile: profile, state: state, coachNotes: [CoachNoteInfo(fact: "Rain barrel by the shed", category: .water, added: Fixtures.day(-10))],
            nudges: [nudge], now: Fixtures.morning, calendar: Fixtures.calendar
        )
        return (snapshot, bed, tomato)
    }

    func testSnapshotContents() throws {
        let (s, _, _) = makeSnapshot()
        XCTAssertEqual(s.today, "2026-07-14")
        XCTAssertEqual(s.timeZone, "America/Chicago")
        XCTAssertEqual(s.generatedAt, "2026-07-14 06:00")
        XCTAssertEqual(s.gardener.name, "Sam")
        XCTAssertEqual(s.location.latitude, 41.88)
        XCTAssertEqual(s.location.longitude, -87.63)
        XCTAssertEqual(s.location.usdaZone, "6a")
        XCTAssertEqual(s.budget.monthlyDollars, 25)
        XCTAssertNil(s.budget.notes)
        XCTAssertTrue(s.preferences.avoidUrine)

        let bed = try XCTUnwrap(s.beds.first)
        XCTAssertEqual(bed.mulch, "straw")
        XCTAssertEqual(bed.water?.lastSoaked, "2026-07-13")
        XCTAssertNotNil(bed.water?.outlook)

        let tomato = try XCTUnwrap(s.plants.first { $0.name == "Big Beef" })
        XCTAssertEqual(tomato.bed, "Back bed")
        XCTAssertEqual(tomato.daysInGround, 20)
        XCTAssertEqual(tomato.staked, true)
        XCTAssertEqual(tomato.lastFed, "2026-07-11")
        XCTAssertEqual(tomato.growingDegreeDays, 420) // 20 days at (80 + 62) / 2 - 50 = 21 each
        let lettuce = try XCTUnwrap(s.plants.first { $0.name == "Butterhead" })
        XCTAssertNil(lettuce.staked, "only crops that need support report staking")

        XCTAssertEqual(s.recentJournal.map { $0.date }, ["2026-07-13", "2026-07-11"])
        XCTAssertEqual(s.recentJournal[1].plant, "Big Beef")
        XCTAssertEqual(s.recentJournal[0].bed, "Back bed")

        let weather = try XCTUnwrap(s.weather)
        XCTAssertEqual(weather.recentDays.count, 14)
        XCTAssertEqual(weather.forecastDays.first?.date, "2026-07-14")
        XCTAssertEqual(weather.forecastDays.count, 8)
        XCTAssertEqual(weather.last7Days?.evapotranspirationInches, 1.4)
        XCTAssertEqual(s.activeNudges.map { $0.title }, ["staking"])
        XCTAssertEqual(s.coachNotes.first?.category, "water")
    }

    func testSnapshotJSONIsCompact() throws {
        let (s, _, _) = makeSnapshot()
        let json = String(data: try GardenSnapshot.makeEncoder().encode(s), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""today":"2026-07-14""#))
        XCTAssertTrue(json.contains(#""timeZone":"America/Chicago""#))
        XCTAssertTrue(json.contains(#""gardener":{"name":"Sam"}"#))
        XCTAssertFalse(json.contains("null"), "empty values are left out")
        XCTAssertFalse(json.contains("Old entry"), "journal is limited to recent entries")
        XCTAssertLessThan(json.count, 20_000)
    }
}

final class APITests: XCTestCase {
    func testDecodesCoachActionsLikeTheBackendSendsThem() throws {
        let json = """
        {"reply":"Nice work. I logged that.","model":"claude-x","actions":[
          {"type":"journal","summary":"Logged watering: deep soak (Back bed), 2026-07-14","date":"2026-07-14","kind":"watering",
           "what":"deep soak","amount":"about an inch","bedName":"Back bed","plantName":"","moisture":null,"notes":""},
          {"type":"plant","summary":"Updated Sungold (fruiting)","plantName":"Sungold","crop":"cherry_tomato","bedName":"",
           "stage":"fruiting","plantedOn":"","staked":true,"count":null,"removed":false,"notes":""},
          {"type":"inventory","summary":"Added Alfalfa to your inventory","action":"add","name":"Alfalfa","category":"fertilizer","quantity":"","notes":""},
          {"type":"budget","summary":"Set your monthly budget to $30","monthlyDollars":30,"notes":""},
          {"type":"fact","summary":"Noted: dog digs in the back bed","fact":"dog digs in the back bed","category":"wildlife"},
          {"summary":"missing type"}
        ]}
        """
        let response = try JSONDecoder().decode(CoachResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.reply, "Nice work. I logged that.")
        XCTAssertEqual(response.actions.count, 5, "a malformed action is skipped, not fatal")

        let journal = response.actions[0]
        XCTAssertEqual(journal.actionType, .journal)
        XCTAssertEqual(journal.journalKind, .watering)
        XCTAssertEqual(journal.day, Fixtures.today)
        XCTAssertNil(journal.moistureReading)

        let plant = response.actions[1]
        XCTAssertEqual(plant.growthStage, .fruiting)
        XCTAssertEqual(plant.staked, true)
        XCTAssertNil(plant.count)
        XCTAssertNil(plant.plantedDay)

        XCTAssertEqual(response.actions[2].inventoryCategory, .fertilizer)
        XCTAssertEqual(response.actions[3].monthlyDollars, 30)
        XCTAssertEqual(response.actions[4].factCategory, .wildlife)
        XCTAssertEqual(response.actions[4].displaySummary, "Noted: dog digs in the back bed")
    }

    func testDecodesDiagnosis() throws {
        let json = """
        {"diagnosis":{"summary":"Hungry, not thirsty.","overall":"nutrient_deficiency","confidence":"medium",
          "findings":[{"issue":"Nitrogen deficiency","category":"deficiency","nutrient":"nitrogen","likelihood":"likely","evidence":"Older leaves"}],
          "fixes":[{"tier":"owned","title":"Your alfalfa","how":"A cup per plant","product":"","price":"","pros":"","cons":"","usesInventoryItem":"Alfalfa"},
                   {"tier":"something_new","title":"New tier","how":"x","product":"","price":"","pros":"","cons":"","usesInventoryItem":""}],
          "soilTestSuggested":true,"soilTestReason":"pH unknown","followUp":"Check in a week","journalNote":"Photo check","photoQualityNote":""},
         "model":"claude-x"}
        """
        let d = try JSONDecoder().decode(DiagnoseResponse.self, from: Data(json.utf8)).diagnosis
        XCTAssertEqual(d.overallValue, .nutrientDeficiency)
        XCTAssertEqual(d.confidenceValue, .medium)
        XCTAssertEqual(d.findings.first?.categoryValue, .deficiency)
        XCTAssertEqual(d.findings.first?.likelihoodValue, .likely)
        XCTAssertEqual(d.fixes.map { $0.tierValue }, [.owned, .branded])
        XCTAssertTrue(d.soilTestSuggested)
    }

    func testEndpointFromBuildSettings() throws {
        XCTAssertNil(CoachEndpoint(host: "", secret: "abc"))
        XCTAssertNil(CoachEndpoint(host: "eb.example.workers.dev", secret: ""))
        XCTAssertNil(CoachEndpoint(host: "$(EB_BACKEND_HOST)", secret: "abc"))
        XCTAssertNil(CoachEndpoint(host: "your-worker.workers.dev", secret: "abc"))
        let endpoint = try XCTUnwrap(CoachEndpoint(host: "https://eb.example.workers.dev/", secret: " abc "))
        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://eb.example.workers.dev")

        let post = endpoint.request(path: "v1/coach", body: Data("{}".utf8))
        XCTAssertEqual(post.url?.absoluteString, "https://eb.example.workers.dev/v1/coach")
        XCTAssertEqual(post.httpMethod, "POST")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(endpoint.request(path: "v1/health", body: nil).httpMethod, "GET")
    }

    func testErrorMapping() {
        let busy = Data(#"{"error":{"code":"busy","message":"The coach is busy right now. Try again in a minute."}}"#.utf8)
        XCTAssertThrowsError(try CoachEndpoint.decode(CoachResponse.self, data: busy, status: 429)) { error in
            XCTAssertEqual(error as? CoachAPIError, .server(status: 429, code: "busy", message: "The coach is busy right now. Try again in a minute."))
            XCTAssertEqual((error as? CoachAPIError)?.userMessage, "The coach is busy right now. Try again in a minute.")
        }
        XCTAssertThrowsError(try CoachEndpoint.decode(CoachResponse.self, data: Data("<html>".utf8), status: 502)) { error in
            XCTAssertEqual(error as? CoachAPIError, .server(status: 502, code: "http_502", message: ""))
        }
        XCTAssertThrowsError(try CoachEndpoint.decode(CoachResponse.self, data: Data("{}".utf8), status: 200)) { error in
            XCTAssertEqual(error as? CoachAPIError, .badResponse)
        }
    }

    func testRequestEncoding() throws {
        let (snapshot, _, _) = SnapshotTestsHelper.snapshot()
        let request = CoachRequest(messages: [ChatTurn(role: .user, text: "How's the back bed?")], garden: snapshot,
                                   context: CoachContext(kind: "nudge", text: "Water now"))
        let json = String(data: try GardenSnapshot.makeEncoder().encode(request), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""messages":[{"role":"user","text":"How's the back bed?"}]"#))
        XCTAssertTrue(json.contains(#""context":{"kind":"nudge","text":"Water now"}"#))
    }

    func testSpeechTextMatchesTheBackend() {
        XCTAssertEqual(
            SpeechText.plain("## Plan\n1. **Water** _deeply_\n2. See [this](https://x.test)\n`code`"),
            "Plan\n1. Water deeply\n2. See this\ncode"
        )
        XCTAssertEqual(SpeechText.plain("- It'll hit 95°F\n- Mulch"), "It'll hit 95 degrees\nMulch")
        XCTAssertEqual(SpeechText.cacheKey("**Hi**"), SpeechText.cacheKey("Hi"))
        XCTAssertNotEqual(SpeechText.cacheKey("Hi"), SpeechText.cacheKey("Hello"))
    }

    func testDemoCoach() {
        let state = Fixtures.state(plants: [Fixtures.plant("Butterhead", crop: "lettuce")], weather: Fixtures.weather())
        let feed = DemoCoach.reply(to: "What should I feed my lettuce?", state: state, profile: GardenProfileInfo(),
                                   now: Fixtures.morning, calendar: Fixtures.calendar)
        XCTAssertTrue(feed.contains("1. Compost or worm castings"), "leafy crops skip urine")
        XCTAssertTrue(feed.hasSuffix(DemoCoach.notice))
        let frost = DemoCoach.reply(to: "Will it frost?", state: state, profile: GardenProfileInfo(), now: Fixtures.morning, calendar: Fixtures.calendar)
        XCTAssertTrue(frost.hasPrefix("No frost in the next week's forecast."))
        XCTAssertEqual(DemoCoach.diagnosis(plantName: "Sungold").overallValue, .nutrientDeficiency)
    }
}

enum SnapshotTestsHelper {
    static func snapshot() -> (GardenSnapshot, BedInfo, PlantInfo) {
        let bed = Fixtures.bed()
        let plant = Fixtures.plant("Big Beef", crop: "tomato", bed: bed)
        let state = Fixtures.state(beds: [bed], plants: [plant])
        let s = GardenSnapshot.make(profile: GardenProfileInfo(), state: state, coachNotes: [], nudges: [], now: Fixtures.morning, calendar: Fixtures.calendar)
        return (s, bed, plant)
    }
}
