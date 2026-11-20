import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Request and response models for the coach backend (backend/src). Field names match the
// backend's JSON exactly; strings that carry vocabulary values stay strings so a newer backend
// can add values without breaking an older app.

// MARK: - Coach chat

public struct ChatTurn: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// Where a chat started, e.g. from a nudge the gardener tapped.
public struct CoachContext: Codable, Hashable, Sendable {
    public var kind: String
    public var text: String

    public init(kind: String, text: String) {
        self.kind = kind
        self.text = text
    }

    public static func nudge(_ nudge: Nudge) -> CoachContext {
        CoachContext(kind: "nudge", text: "\(nudge.title). \(nudge.body)")
    }
}

public struct CoachRequest: Codable, Sendable {
    public var messages: [ChatTurn]
    public var garden: GardenSnapshot
    public var context: CoachContext?

    public init(messages: [ChatTurn], garden: GardenSnapshot, context: CoachContext? = nil) {
        self.messages = messages
        self.garden = garden
        self.context = context
    }
}

public struct CoachResponse: Codable, Sendable {
    public var reply: String
    public var actions: [CoachAction]
    public var model: String?

    public init(reply: String, actions: [CoachAction] = [], model: String? = nil) {
        self.reply = reply
        self.actions = actions
        self.model = model
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decode(String.self, forKey: .reply)
        // One malformed action shouldn't lose the whole reply.
        let raw: [FailableAction]? = try? c.decodeIfPresent([FailableAction].self, forKey: .actions)
        actions = (raw ?? []).compactMap { $0.value }
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }

    private struct FailableAction: Decodable {
        let value: CoachAction?
        init(from decoder: Decoder) throws {
            value = try? CoachAction(from: decoder)
        }
    }
}

/// A record-keeping change the coach made during a chat (see COACH_TOOLS in backend/src/tools.ts).
/// One flat shape covers every type; fields that don't apply are nil.
public struct CoachAction: Codable, Hashable, Sendable {
    public enum ActionType: String, Sendable {
        case journal, plant, bed, inventory, budget, fact
    }

    public var type: String
    public var summary: String?

    // journal
    public var date: String?
    /// Journal kind for "journal", bed kind for "bed".
    public var kind: String?
    public var what: String?
    public var amount: String?
    public var bedName: String?
    public var plantName: String?
    public var moisture: String?
    public var notes: String?

    // plant
    public var crop: String?
    public var stage: String?
    public var plantedOn: String?
    public var staked: Bool?
    public var count: Int?
    public var removed: Bool?

    // bed
    public var soilType: String?
    public var sun: String?
    public var irrigation: String?
    public var mulch: String?
    public var areaSqFt: Double?
    public var soilPH: Double?
    public var soilTestNotes: String?

    // inventory ("add" or "remove")
    public var action: String?
    public var name: String?
    public var category: String?
    public var quantity: String?

    // budget
    public var monthlyDollars: Double?

    // fact
    public var fact: String?

    public init(type: ActionType, summary: String) {
        self.type = type.rawValue
        self.summary = summary
    }

    public var actionType: ActionType? { ActionType(rawValue: type) }
    public var day: LocalDay? { date.flatMap { LocalDay($0) } }
    public var plantedDay: LocalDay? { plantedOn.flatMap { LocalDay($0) } }
    public var journalKind: JournalKind? { kind.flatMap { JournalKind(rawValue: $0) } }
    public var bedKind: BedKind? { kind.flatMap { BedKind(rawValue: $0) } }
    public var moistureReading: MoistureReading? { moisture.flatMap { MoistureReading(rawValue: $0) } }
    public var growthStage: GrowthStage? { stage.flatMap { GrowthStage(rawValue: $0) } }
    public var soil: SoilType? { soilType.flatMap { SoilType(rawValue: $0) } }
    public var sunExposure: SunExposure? { sun.flatMap { SunExposure(rawValue: $0) } }
    public var irrigationKind: IrrigationKind? { irrigation.flatMap { IrrigationKind(rawValue: $0) } }
    public var inventoryCategory: InventoryCategory? { category.flatMap { InventoryCategory(rawValue: $0) } }
    public var factCategory: FactCategory? { category.flatMap { FactCategory(rawValue: $0) } }

    /// A short line for the chat ("Logged watering: ...").
    public var displaySummary: String {
        if let s = summary, !s.isEmpty { return s }
        switch actionType {
        case .journal?: return "Logged \(what ?? "an entry")"
        case .plant?: return "Updated \(plantName ?? "a plant")"
        case .bed?: return "Updated \(bedName ?? "a bed")"
        case .inventory?: return "Updated your inventory"
        case .budget?: return "Updated your budget"
        case .fact?: return "Noted: \(fact ?? "")"
        case nil: return "Updated your garden"
        }
    }
}

// MARK: - Photo diagnosis

public struct ImagePayload: Codable, Sendable {
    public var mediaType: String
    /// Base64, no line breaks.
    public var data: String

    public init(mediaType: String, data: String) {
        self.mediaType = mediaType
        self.data = data
    }
}

public struct DiagnoseRequest: Codable, Sendable {
    public var image: ImagePayload
    public var plantName: String
    public var note: String
    public var garden: GardenSnapshot

    public init(image: ImagePayload, plantName: String, note: String, garden: GardenSnapshot) {
        self.image = image
        self.plantName = plantName
        self.note = note
        self.garden = garden
    }
}

public struct DiagnoseResponse: Codable, Sendable {
    public var diagnosis: Diagnosis
    public var model: String?
}

public enum DiagnosisOverall: String, Codable, CaseIterable, Sendable {
    case healthy
    case waterStress = "water_stress"
    case nutrientDeficiency = "nutrient_deficiency"
    case nutrientToxicity = "nutrient_toxicity"
    case pestOrDisease = "pest_or_disease"
    case other
    case unclear

    public var displayName: String {
        switch self {
        case .healthy: return "Looks healthy"
        case .waterStress: return "Water stress"
        case .nutrientDeficiency: return "Nutrient deficiency"
        case .nutrientToxicity: return "Too much fertilizer"
        case .pestOrDisease: return "Pest or disease"
        case .other: return "Something else"
        case .unclear: return "Hard to tell"
        }
    }

    public var symbol: String {
        switch self {
        case .healthy: return "checkmark.seal.fill"
        case .waterStress: return "drop.triangle.fill"
        case .nutrientDeficiency: return "leaf.fill"
        case .nutrientToxicity: return "exclamationmark.triangle.fill"
        case .pestOrDisease: return "ant.fill"
        case .other: return "questionmark.circle.fill"
        case .unclear: return "eye.trianglebadge.exclamationmark.fill"
        }
    }
}

public enum DiagnosisConfidence: String, Codable, CaseIterable, Sendable {
    case high, medium, low

    public var displayName: String {
        switch self {
        case .high: return "Fairly sure"
        case .medium: return "Somewhat sure"
        case .low: return "Not sure"
        }
    }
}

public enum FindingLikelihood: String, Codable, CaseIterable, Sendable {
    case likely, possible, unlikely

    public var displayName: String {
        switch self {
        case .likely: return "Likely"
        case .possible: return "Possible"
        case .unlikely: return "Unlikely"
        }
    }
}

public enum FindingCategory: String, Codable, CaseIterable, Sendable {
    case underwatering, overwatering, deficiency, toxicity
    case phLockout = "ph_lockout"
    case pest, disease, environmental, other

    public var displayName: String {
        switch self {
        case .underwatering: return "Underwatering"
        case .overwatering: return "Overwatering"
        case .deficiency: return "Deficiency"
        case .toxicity: return "Toxicity or burn"
        case .phLockout: return "pH lockout"
        case .pest: return "Pest"
        case .disease: return "Disease"
        case .environmental: return "Weather or site"
        case .other: return "Other"
        }
    }
}

public struct Diagnosis: Codable, Hashable, Sendable {
    public struct Finding: Codable, Hashable, Sendable {
        public var issue: String
        public var category: String
        public var nutrient: String
        public var likelihood: String
        public var evidence: String

        public init(issue: String, category: String, nutrient: String = "", likelihood: String, evidence: String) {
            self.issue = issue
            self.category = category
            self.nutrient = nutrient
            self.likelihood = likelihood
            self.evidence = evidence
        }

        public var categoryValue: FindingCategory { FindingCategory(rawValue: category) ?? .other }
        public var likelihoodValue: FindingLikelihood { FindingLikelihood(rawValue: likelihood) ?? .possible }
    }

    public struct Fix: Codable, Hashable, Sendable {
        public var tier: String
        public var title: String
        public var how: String
        public var product: String
        public var price: String
        public var pros: String
        public var cons: String
        public var usesInventoryItem: String

        public init(
            tier: String, title: String, how: String, product: String = "", price: String = "",
            pros: String = "", cons: String = "", usesInventoryItem: String = ""
        ) {
            self.tier = tier
            self.title = title
            self.how = how
            self.product = product
            self.price = price
            self.pros = pros
            self.cons = cons
            self.usesInventoryItem = usesInventoryItem
        }

        public var tierValue: Tier { Tier(rawValue: tier) ?? .branded }
    }

    public var summary: String
    public var overall: String
    public var confidence: String
    public var findings: [Finding]
    public var fixes: [Fix]
    public var soilTestSuggested: Bool
    public var soilTestReason: String
    public var followUp: String
    public var journalNote: String
    public var photoQualityNote: String

    public init(
        summary: String, overall: String, confidence: String, findings: [Finding], fixes: [Fix],
        soilTestSuggested: Bool = false, soilTestReason: String = "", followUp: String = "",
        journalNote: String = "", photoQualityNote: String = ""
    ) {
        self.summary = summary
        self.overall = overall
        self.confidence = confidence
        self.findings = findings
        self.fixes = fixes
        self.soilTestSuggested = soilTestSuggested
        self.soilTestReason = soilTestReason
        self.followUp = followUp
        self.journalNote = journalNote
        self.photoQualityNote = photoQualityNote
    }

    public var overallValue: DiagnosisOverall { DiagnosisOverall(rawValue: overall) ?? .unclear }
    public var confidenceValue: DiagnosisConfidence { DiagnosisConfidence(rawValue: confidence) ?? .low }
}

// MARK: - Nudge wording

public struct NudgeDraft: Codable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var body: String

    public init(id: String, kind: String, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
    }

    public init(_ nudge: Nudge) {
        self.init(id: nudge.id, kind: nudge.kind.rawValue, title: nudge.title, body: nudge.body)
    }
}

public struct PhraseRequest: Codable, Sendable {
    public var nudges: [NudgeDraft]

    public init(nudges: [NudgeDraft]) {
        self.nudges = nudges
    }
}

public struct NudgePhrasing: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public struct PhraseResponse: Codable, Sendable {
    public var phrasings: [NudgePhrasing]
}

// MARK: - Voice and health

public struct SpeakRequest: Codable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct HealthResponse: Codable, Sendable {
    public struct PersonaFile: Codable, Hashable, Sendable {
        public var name: String
        public var status: String
    }

    public var ok: Bool
    public var apiVersion: String
    public var model: String?
    public var claudeConfigured: Bool?
    public var voiceAvailable: Bool?
    public var persona: [PersonaFile]?
}

// MARK: - Transport

public struct APIErrorBody: Codable, Sendable {
    public struct Detail: Codable, Sendable {
        public var code: String
        public var message: String
    }

    public var error: Detail
}

public enum CoachAPIError: Error, Equatable, Sendable {
    /// No backend address or secret in the build settings.
    case notConfigured
    /// The backend answered with an error.
    case server(status: Int, code: String, message: String)
    /// The phone couldn't reach the backend.
    case network(String)
    /// The response wasn't what the app expected.
    case badResponse

    /// Wording for the gardener.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "The coach isn't connected yet, so the app is in demo mode. Settings explains how to connect it."
        case let .server(status, code, message):
            switch code {
            case "unauthorized": return "The app's key for the coach doesn't match the server. Check the app secret in the build settings."
            case "busy": return "The coach is busy right now. Try again in a minute."
            case "declined": return message
            case "voice_off": return "David's voice isn't set up yet."
            default:
                if status >= 500 { return "The coach ran into a problem (\(code)). Try again in a minute." }
                return message.isEmpty ? "Something went wrong (\(code))." : message
            }
        case .network:
            return "Couldn't reach the coach. Check your connection and try again."
        case .badResponse:
            return "The coach sent back something unexpected. Try again."
        }
    }
}

/// Where the backend lives and how the app proves it's the app.
public struct CoachEndpoint: Sendable {
    public var baseURL: URL
    public var secret: String

    public init(baseURL: URL, secret: String) {
        self.baseURL = baseURL
        self.secret = secret
    }

    /// Reads the host and secret the build put in Info.plist. Returns nil when either is missing
    /// or still a placeholder, which puts the app in demo mode.
    public init?(host: String?, secret: String?) {
        let h = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let s = (secret ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !s.isEmpty, !h.contains("$("), !s.contains("$("), !h.hasPrefix("your-"),
              let url = URL(string: "https://\(h)") else { return nil }
        self.init(baseURL: url, secret: s)
    }

    public func request(path: String, body: Data?, timeout: TimeInterval = 90) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    /// Turns a response into a value or a CoachAPIError.
    public static func decode<T: Decodable>(_ type: T.Type, data: Data, status: Int) throws -> T {
        guard (200..<300).contains(status) else {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw CoachAPIError.server(status: status, code: body.error.code, message: body.error.message)
            }
            throw CoachAPIError.server(status: status, code: "http_\(status)", message: "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CoachAPIError.badResponse
        }
    }
}
