import Foundation
import SwiftData
import GardenCore

// The app's records, stored on the phone with SwiftData. There are no relationships between
// models: plants point at beds and journal entries at beds or plants by UUID, which keeps
// migrations and deletes simple. Vocabulary values are stored as raw strings that match
// GardenCore's enums (and the backend's vocab.ts).

@Model
final class GardenProfile {
    var gardenerName: String = ""
    var locationLabel: String = ""
    var latitude: Double?
    var longitude: Double?
    var timeZoneID: String?
    var usdaZone: String = ""
    /// "YYYY-MM-DD"
    var lastSpringFrost: String?
    var firstFallFrost: String?
    var monthlyBudget: Double?
    var budgetNotes: String = ""
    var avoidUrine: Bool = false
    var onboarded: Bool = false

    // Coach
    var voiceEnabled: Bool = false

    // Nudges (see NudgeSettings for what each one does)
    var nudgesEnabled: Bool = true
    var maxNudgesPerDay: Int = 2
    var quietStartMinute: Int = 21 * 60
    var quietEndMinute: Int = 7 * 60
    var deliveryMinute: Int = 7 * 60 + 30
    var foliarIntervalDays: Int = 21

    var created: Date = Date()

    init() {}

    var nudgeSettings: NudgeSettings {
        var s = NudgeSettings.standard
        s.enabled = nudgesEnabled
        s.maxPerDay = max(1, maxNudgesPerDay)
        s.quietStartMinute = quietStartMinute
        s.quietEndMinute = quietEndMinute
        s.deliveryMinute = deliveryMinute
        s.foliarIntervalDays = max(7, foliarIntervalDays)
        return s
    }

    var info: GardenProfileInfo {
        GardenProfileInfo(
            gardenerName: gardenerName,
            locationLabel: locationLabel,
            latitude: latitude,
            longitude: longitude,
            timeZoneID: timeZoneID,
            usdaZone: usdaZone,
            lastSpringFrost: lastSpringFrost.flatMap { LocalDay($0) },
            firstFallFrost: firstFallFrost.flatMap { LocalDay($0) },
            monthlyBudget: monthlyBudget,
            budgetNotes: budgetNotes,
            avoidUrine: avoidUrine
        )
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }
}

@Model
final class Bed {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = BedKind.raised.rawValue
    var areaSqFt: Double?
    var soilRaw: String = SoilType.unknown.rawValue
    var sunRaw: String = SunExposure.fullSun.rawValue
    var irrigationRaw: String = IrrigationKind.hose.rawValue
    var mulch: String = ""
    var soilPH: Double?
    var soilTestNotes: String = ""
    var notes: String = ""
    var created: Date = Date()

    init(name: String, kind: BedKind = .raised, soil: SoilType = .unknown, sun: SunExposure = .fullSun) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.soilRaw = soil.rawValue
        self.sunRaw = sun.rawValue
        self.created = Date()
    }

    var kind: BedKind {
        get { BedKind(rawValue: kindRaw) ?? .raised }
        set { kindRaw = newValue.rawValue }
    }

    var soil: SoilType {
        get { SoilType(rawValue: soilRaw) ?? .unknown }
        set { soilRaw = newValue.rawValue }
    }

    var sun: SunExposure {
        get { SunExposure(rawValue: sunRaw) ?? .fullSun }
        set { sunRaw = newValue.rawValue }
    }

    var irrigation: IrrigationKind {
        get { IrrigationKind(rawValue: irrigationRaw) ?? .hose }
        set { irrigationRaw = newValue.rawValue }
    }

    var info: BedInfo {
        BedInfo(
            id: id, name: name, kind: kind, areaSqFt: areaSqFt, soilType: soil, sun: sun, irrigation: irrigation,
            mulch: mulch, soilPH: soilPH, soilTestNotes: soilTestNotes, notes: notes
        )
    }
}

@Model
final class Plant {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var cropID: String?
    var bedID: UUID?
    /// "YYYY-MM-DD"
    var plantedOn: String?
    var stageRaw: String = GrowthStage.vegetative.rawValue
    var count: Int = 1
    var staked: Bool = false
    var notes: String = ""
    var created: Date = Date()

    init(name: String, cropID: String?, bedID: UUID?, plantedOn: LocalDay?, stage: GrowthStage = .vegetative) {
        self.id = UUID()
        self.name = name
        self.cropID = cropID
        self.bedID = bedID
        self.plantedOn = plantedOn?.string
        self.stageRaw = stage.rawValue
        self.created = Date()
    }

    var stage: GrowthStage {
        get { GrowthStage(rawValue: stageRaw) ?? .vegetative }
        set { stageRaw = newValue.rawValue }
    }

    var plantedDay: LocalDay? {
        get { plantedOn.flatMap { LocalDay($0) } }
        set { plantedOn = newValue?.string }
    }

    var crop: CropProfile { CropCatalog.profile(for: cropID) }

    var info: PlantInfo {
        PlantInfo(id: id, name: name, cropID: cropID, bedID: bedID, plantedOn: plantedDay, stage: stage, count: count, staked: staked, notes: notes)
    }
}

@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID = UUID()
    /// "YYYY-MM-DD" in the garden's time zone.
    var day: String = ""
    var kindRaw: String = JournalKind.observation.rawValue
    var what: String = ""
    var amount: String = ""
    var bedID: UUID?
    var plantID: UUID?
    var bedName: String = ""
    var plantName: String = ""
    var moistureRaw: String?
    var waterInches: Double?
    var notes: String = ""
    /// Who wrote it: "you", "coach", "nudge" or "photo".
    var source: String = "you"
    /// Set it with `setPhoto(_:)` so `photoAdded` stays in step.
    @Attribute(.externalStorage) var photo: Data?
    /// When the photo was added or last replaced; nil when there's no photo. Lets lists find
    /// photo entries without loading the images, and tells thumbnails when to refresh.
    var photoAdded: Date?
    /// JSON of a GardenCore Diagnosis, for photo checks.
    var diagnosisData: Data?
    var created: Date = Date()

    init(day: LocalDay, kind: JournalKind, what: String, source: String = "you") {
        self.id = UUID()
        self.day = day.string
        self.kindRaw = kind.rawValue
        self.what = what
        self.source = source
        self.created = Date()
    }

    var kind: JournalKind {
        get { JournalKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var localDay: LocalDay {
        get { LocalDay(day) ?? LocalDay(Date(), calendar: .current) }
        set { day = newValue.string }
    }

    var moisture: MoistureReading? {
        get { moistureRaw.flatMap { MoistureReading(rawValue: $0) } }
        set { moistureRaw = newValue?.rawValue }
    }

    var diagnosis: Diagnosis? {
        guard let data = diagnosisData else { return nil }
        return try? JSONDecoder().decode(Diagnosis.self, from: data)
    }

    var hasPhoto: Bool { photoAdded != nil }

    func setPhoto(_ data: Data?) {
        photo = data
        photoAdded = data == nil ? nil : Date()
    }

    /// For the bed and plant records; nil when there's no photo.
    var progressPhoto: ProgressPhoto? {
        guard hasPhoto else { return nil }
        return ProgressPhoto(id: id, day: localDay, bedID: bedID, plantID: plantID, created: created)
    }

    var info: JournalInfo {
        JournalInfo(
            id: id, day: localDay, kind: kind, what: what, amount: amount, bedID: bedID, plantID: plantID,
            bedName: bedName, plantName: plantName, moisture: moisture, waterInches: waterInches, notes: notes
        )
    }
}

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = InventoryCategory.other.rawValue
    var quantity: String = ""
    var notes: String = ""
    var created: Date = Date()

    init(name: String, category: InventoryCategory, quantity: String = "") {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.quantity = quantity
        self.created = Date()
    }

    var category: InventoryCategory {
        get { InventoryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var info: InventoryInfo {
        InventoryInfo(id: id, name: name, category: category, quantity: quantity, notes: notes)
    }
}

/// A lasting fact the coach was asked to remember.
@Model
final class CoachNote {
    @Attribute(.unique) var id: UUID = UUID()
    var fact: String = ""
    var categoryRaw: String = FactCategory.other.rawValue
    /// "YYYY-MM-DD"
    var added: String = ""
    var created: Date = Date()

    init(fact: String, category: FactCategory, added: LocalDay) {
        self.id = UUID()
        self.fact = fact
        self.categoryRaw = category.rawValue
        self.added = added.string
        self.created = Date()
    }

    var info: CoachNoteInfo {
        CoachNoteInfo(
            fact: fact,
            category: FactCategory(rawValue: categoryRaw) ?? .other,
            added: LocalDay(added) ?? LocalDay(created, calendar: .current)
        )
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID = UUID()
    /// "user" or "assistant"
    var role: String = "user"
    var text: String = ""
    /// One line per record the coach updated during this reply.
    var actionLines: [String] = []
    /// The nudge this conversation started from, if any.
    var contextText: String?
    var isDemo: Bool = false
    var created: Date = Date()

    init(role: ChatTurn.Role, text: String, actionLines: [String] = [], contextText: String? = nil, isDemo: Bool = false) {
        self.id = UUID()
        self.role = role.rawValue
        self.text = text
        self.actionLines = actionLines
        self.contextText = contextText
        self.isDemo = isDemo
        self.created = Date()
    }

    var isUser: Bool { role == ChatTurn.Role.user.rawValue }
}

enum Schema1 {
    static let models: [any PersistentModel.Type] = [
        GardenProfile.self, Bed.self, Plant.self, JournalEntry.self, InventoryItem.self, CoachNote.self, ChatMessage.self,
    ]
}
