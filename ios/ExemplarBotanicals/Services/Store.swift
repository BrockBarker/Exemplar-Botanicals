import Foundation
import SwiftData
import GardenCore

/// Small JSON files in Application Support for things that aren't garden records:
/// the weather history, the nudge ledger and nudge wording.
enum Store {
    static let weatherFile = "weather.json"
    static let ledgerFile = "nudges.json"
    static let phrasingFile = "nudge-wording.json"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Garden", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// A short stable hash (FNV-1a) for cache keys.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Everything about the garden, loaded from SwiftData in one go.
struct LoadedGarden {
    let profile: GardenProfile
    let beds: [Bed]
    let plants: [Plant]
    let journal: [JournalEntry]
    let inventory: [InventoryItem]
    let notes: [CoachNote]

    func state(weather: WeatherReport?) -> GardenState {
        GardenState(
            beds: beds.map { $0.info },
            plants: plants.map { $0.info },
            journal: journal.map { $0.info },
            inventory: inventory.map { $0.info },
            weather: weather,
            lastSpringFrost: profile.lastSpringFrost.flatMap { LocalDay($0) },
            firstFallFrost: profile.firstFallFrost.flatMap { LocalDay($0) }
        )
    }
}

@MainActor
enum GardenRepository {
    static func existingProfile(_ context: ModelContext) -> GardenProfile? {
        var descriptor = FetchDescriptor<GardenProfile>(sortBy: [SortDescriptor(\.created)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// The gardener's profile, created on first use.
    static func profile(_ context: ModelContext) -> GardenProfile {
        if let existing = existingProfile(context) { return existing }
        let profile = GardenProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    static func load(_ context: ModelContext) -> LoadedGarden {
        LoadedGarden(
            profile: profile(context),
            beds: (try? context.fetch(FetchDescriptor<Bed>(sortBy: [SortDescriptor(\.created)]))) ?? [],
            plants: (try? context.fetch(FetchDescriptor<Plant>(sortBy: [SortDescriptor(\.created)]))) ?? [],
            journal: (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.created)]))) ?? [],
            inventory: (try? context.fetch(FetchDescriptor<InventoryItem>(sortBy: [SortDescriptor(\.created)]))) ?? [],
            notes: (try? context.fetch(FetchDescriptor<CoachNote>(sortBy: [SortDescriptor(\.created)]))) ?? []
        )
    }

    /// Entries saved before `photoAdded` existed (photo checks) get it filled in once, so they
    /// show up in the bed and plant galleries.
    static func backfillPhotoDates(_ context: ModelContext) {
        let key = "eb.backfill.photoAdded.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        var changed = false
        for entry in entries where entry.photoAdded == nil && entry.photo != nil {
            entry.photoAdded = entry.created
            changed = true
        }
        if changed { try? context.save() }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Foliar sprays used to default to every 14 days; 21 is plenty. Gardeners still on the old
    /// default move to the new one once; anyone who picked their own interval keeps it.
    static func relaxFoliarDefault(_ context: ModelContext) {
        let key = "eb.migrate.foliar21.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if let profile = existingProfile(context), profile.foliarIntervalDays == 14 {
            profile.foliarIntervalDays = 21
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    static func chatHistory(_ context: ModelContext) -> [ChatMessage] {
        (try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.created)]))) ?? []
    }
}
