import Foundation

// Plain value types for the garden. The app keeps its records in SwiftData and maps them to
// these so the logic below (and its tests) doesn't depend on the database.

public struct BedInfo: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: BedKind
    public var areaSqFt: Double?
    public var soilType: SoilType
    public var sun: SunExposure
    public var irrigation: IrrigationKind
    /// Mulch type in plain words ("straw"); empty or "none" means bare soil.
    public var mulch: String
    public var soilPH: Double?
    public var soilTestNotes: String
    public var notes: String

    public init(
        id: UUID = UUID(), name: String, kind: BedKind = .raised, areaSqFt: Double? = nil,
        soilType: SoilType = .unknown, sun: SunExposure = .fullSun, irrigation: IrrigationKind = .hose,
        mulch: String = "", soilPH: Double? = nil, soilTestNotes: String = "", notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.areaSqFt = areaSqFt
        self.soilType = soilType
        self.sun = sun
        self.irrigation = irrigation
        self.mulch = mulch
        self.soilPH = soilPH
        self.soilTestNotes = soilTestNotes
        self.notes = notes
    }

    public var isMulched: Bool {
        let m = mulch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !m.isEmpty && m != "none" && m != "no"
    }
}

public struct PlantInfo: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var cropID: String?
    public var bedID: UUID?
    public var plantedOn: LocalDay?
    public var stage: GrowthStage
    public var count: Int
    public var staked: Bool
    public var notes: String

    public init(
        id: UUID = UUID(), name: String, cropID: String? = nil, bedID: UUID? = nil, plantedOn: LocalDay? = nil,
        stage: GrowthStage = .vegetative, count: Int = 1, staked: Bool = false, notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.cropID = cropID
        self.bedID = bedID
        self.plantedOn = plantedOn
        self.stage = stage
        self.count = count
        self.staked = staked
        self.notes = notes
    }

    public var crop: CropProfile { CropCatalog.profile(for: cropID) }
}

public struct JournalInfo: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var day: LocalDay
    public var kind: JournalKind
    public var what: String
    public var amount: String
    public var bedID: UUID?
    public var plantID: UUID?
    public var bedName: String
    public var plantName: String
    public var moisture: MoistureReading?
    /// Water applied in inches, when known (set by the quick "I watered" buttons).
    public var waterInches: Double?
    public var notes: String

    public init(
        id: UUID = UUID(), day: LocalDay, kind: JournalKind, what: String, amount: String = "",
        bedID: UUID? = nil, plantID: UUID? = nil, bedName: String = "", plantName: String = "",
        moisture: MoistureReading? = nil, waterInches: Double? = nil, notes: String = ""
    ) {
        self.id = id
        self.day = day
        self.kind = kind
        self.what = what
        self.amount = amount
        self.bedID = bedID
        self.plantID = plantID
        self.bedName = bedName
        self.plantName = plantName
        self.moisture = moisture
        self.waterInches = waterInches
        self.notes = notes
    }

    /// True when the entry has no specific bed or plant, so it applies garden-wide.
    public var isGardenWide: Bool { bedID == nil && plantID == nil && bedName.isEmpty && plantName.isEmpty }

    /// Does this entry apply to the plant (directly, through its bed, or garden-wide)?
    public func applies(to plant: PlantInfo, bedName plantBedName: String?) -> Bool {
        if let pid = plantID { return pid == plant.id }
        if !plantName.isEmpty { return plantName.caseInsensitiveCompare(plant.name) == .orderedSame }
        if let bid = bedID { return bid == plant.bedID }
        if !bedName.isEmpty, let b = plantBedName { return bedName.caseInsensitiveCompare(b) == .orderedSame }
        return isGardenWide
    }

    /// Does this entry apply to the bed (directly, or garden-wide)?
    public func applies(to bed: BedInfo) -> Bool {
        if let bid = bedID { return bid == bed.id }
        if !bedName.isEmpty { return bedName.caseInsensitiveCompare(bed.name) == .orderedSame }
        return isGardenWide && plantID == nil && plantName.isEmpty
    }
}

public struct InventoryInfo: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var category: InventoryCategory
    public var quantity: String
    public var notes: String

    public init(id: UUID = UUID(), name: String, category: InventoryCategory = .other, quantity: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.notes = notes
    }
}

/// The gardener and where the garden is.
public struct GardenProfileInfo: Hashable, Sendable {
    public var gardenerName: String
    public var locationLabel: String
    public var latitude: Double?
    public var longitude: Double?
    public var timeZoneID: String?
    /// USDA hardiness zone, e.g. "7a"; empty when unknown.
    public var usdaZone: String
    public var lastSpringFrost: LocalDay?
    public var firstFallFrost: LocalDay?
    public var monthlyBudget: Double?
    public var budgetNotes: String
    /// Leaves diluted urine out of suggestions when the gardener would rather not use it.
    public var avoidUrine: Bool

    public init(
        gardenerName: String = "", locationLabel: String = "", latitude: Double? = nil, longitude: Double? = nil,
        timeZoneID: String? = nil, usdaZone: String = "", lastSpringFrost: LocalDay? = nil, firstFallFrost: LocalDay? = nil,
        monthlyBudget: Double? = nil, budgetNotes: String = "", avoidUrine: Bool = false
    ) {
        self.gardenerName = gardenerName
        self.locationLabel = locationLabel
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
        self.usdaZone = usdaZone
        self.lastSpringFrost = lastSpringFrost
        self.firstFallFrost = firstFallFrost
        self.monthlyBudget = monthlyBudget
        self.budgetNotes = budgetNotes
        self.avoidUrine = avoidUrine
    }

    public var hasLocation: Bool { latitude != nil && longitude != nil }
}

/// A lasting fact the coach was asked to remember ("rain barrel by the shed").
public struct CoachNoteInfo: Hashable, Sendable {
    public var fact: String
    public var category: FactCategory
    public var added: LocalDay

    public init(fact: String, category: FactCategory = .other, added: LocalDay) {
        self.fact = fact
        self.category = category
        self.added = added
    }
}
