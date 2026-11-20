import Foundation
import SwiftData
import GardenCore

/// Applies the record-keeping changes the coach made during a chat (see COACH_TOOLS in
/// backend/src/tools.ts) to the garden's records. Names are matched loosely ("the Sungold").
@MainActor
enum ActionApplier {
    /// Returns one line per change, for the chat.
    static func apply(_ actions: [CoachAction], context: ModelContext, today: LocalDay) -> [String] {
        var lines: [String] = []
        for action in actions {
            let garden = GardenRepository.load(context)
            let applied: Bool
            switch action.actionType {
            case .journal?: applied = journal(action, garden: garden, context: context, today: today)
            case .plant?: applied = plant(action, garden: garden, context: context)
            case .bed?: applied = bed(action, garden: garden, context: context)
            case .inventory?: applied = inventory(action, garden: garden, context: context)
            case .budget?: applied = budget(action, garden: garden)
            case .fact?: applied = fact(action, garden: garden, context: context, today: today)
            case nil: applied = false
            }
            if applied {
                lines.append(action.displaySummary)
                try? context.save()
            }
        }
        return lines
    }

    private static func findBed(_ name: String?, in beds: [Bed]) -> Bed? {
        guard let name = name, !name.isEmpty else { return nil }
        return NameMatch.index(of: name, in: beds.map { $0.name }).map { beds[$0] }
    }

    private static func findPlant(_ name: String?, in plants: [Plant]) -> Plant? {
        guard let name = name, !name.isEmpty else { return nil }
        return NameMatch.index(of: name, in: plants.map { $0.name }).map { plants[$0] }
    }

    private static func clean(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func journal(_ a: CoachAction, garden: LoadedGarden, context: ModelContext, today: LocalDay) -> Bool {
        let what = clean(a.what)
        guard !what.isEmpty else { return false }
        let entry = JournalEntry(day: a.day ?? today, kind: a.journalKind ?? .other, what: what, source: "coach")
        entry.amount = clean(a.amount)
        entry.notes = clean(a.notes)
        entry.moisture = a.moistureReading
        let plant = findPlant(a.plantName, in: garden.plants)
        let bed = findBed(a.bedName, in: garden.beds) ?? plant.flatMap { p in garden.beds.first { $0.id == p.bedID } }
        entry.plantID = plant?.id
        entry.plantName = plant?.name ?? clean(a.plantName)
        entry.bedID = bed?.id
        entry.bedName = bed?.name ?? clean(a.bedName)
        context.insert(entry)
        return true
    }

    private static func plant(_ a: CoachAction, garden: LoadedGarden, context: ModelContext) -> Bool {
        let name = clean(a.plantName)
        guard !name.isEmpty else { return false }
        let existing = findPlant(name, in: garden.plants)
        if a.removed == true {
            guard let plant = existing else { return false }
            context.delete(plant)
            return true
        }
        let cropID = clean(a.crop)
        let validCrop = CropCatalog.all.contains { $0.id == cropID } ? cropID : nil
        let bed = findBed(a.bedName, in: garden.beds)
        let plant: Plant
        if let found = existing {
            plant = found
        } else {
            plant = Plant(
                name: name,
                cropID: validCrop ?? CropCatalog.guess(from: name)?.id,
                bedID: bed?.id ?? (garden.beds.count == 1 ? garden.beds[0].id : nil),
                plantedOn: a.plantedDay,
                stage: a.growthStage ?? .vegetative
            )
            context.insert(plant)
        }
        if let crop = validCrop { plant.cropID = crop }
        if let bed = bed { plant.bedID = bed.id }
        if let stage = a.growthStage { plant.stage = stage }
        if let planted = a.plantedDay { plant.plantedDay = planted }
        if let staked = a.staked { plant.staked = staked }
        if let count = a.count, count > 0 { plant.count = count }
        let notes = clean(a.notes)
        if !notes.isEmpty { plant.notes = plant.notes.isEmpty ? notes : plant.notes + "\n" + notes }
        return true
    }

    private static func bed(_ a: CoachAction, garden: LoadedGarden, context: ModelContext) -> Bool {
        let name = clean(a.bedName)
        guard !name.isEmpty else { return false }
        let bed: Bed
        if let found = findBed(name, in: garden.beds) {
            bed = found
        } else {
            bed = Bed(name: name)
            context.insert(bed)
        }
        if let kind = a.bedKind { bed.kind = kind }
        if let soil = a.soil { bed.soil = soil }
        if let sun = a.sunExposure { bed.sun = sun }
        if let irrigation = a.irrigationKind { bed.irrigation = irrigation }
        if !clean(a.mulch).isEmpty { bed.mulch = clean(a.mulch) }
        if let area = a.areaSqFt, area > 0 { bed.areaSqFt = area }
        if let ph = a.soilPH { bed.soilPH = ph }
        if !clean(a.soilTestNotes).isEmpty { bed.soilTestNotes = clean(a.soilTestNotes) }
        let notes = clean(a.notes)
        if !notes.isEmpty { bed.notes = bed.notes.isEmpty ? notes : bed.notes + "\n" + notes }
        return true
    }

    private static func inventory(_ a: CoachAction, garden: LoadedGarden, context: ModelContext) -> Bool {
        let name = clean(a.name)
        guard !name.isEmpty else { return false }
        let match = NameMatch.index(of: name, in: garden.inventory.map { $0.name }).map { garden.inventory[$0] }
        if a.action == "remove" {
            guard let item = match else { return false }
            context.delete(item)
            return true
        }
        let item: InventoryItem
        if let found = match {
            item = found
        } else {
            item = InventoryItem(name: name, category: a.inventoryCategory ?? .other)
            context.insert(item)
        }
        if let category = a.inventoryCategory { item.category = category }
        if !clean(a.quantity).isEmpty { item.quantity = clean(a.quantity) }
        if !clean(a.notes).isEmpty { item.notes = clean(a.notes) }
        return true
    }

    private static func budget(_ a: CoachAction, garden: LoadedGarden) -> Bool {
        guard let dollars = a.monthlyDollars, dollars >= 0 else { return false }
        garden.profile.monthlyBudget = dollars
        if !clean(a.notes).isEmpty { garden.profile.budgetNotes = clean(a.notes) }
        return true
    }

    private static func fact(_ a: CoachAction, garden: LoadedGarden, context: ModelContext, today: LocalDay) -> Bool {
        let fact = clean(a.fact)
        guard !fact.isEmpty else { return false }
        if garden.notes.contains(where: { $0.fact.caseInsensitiveCompare(fact) == .orderedSame }) { return false }
        context.insert(CoachNote(fact: fact, category: a.factCategory ?? .other, added: today))
        return true
    }
}
