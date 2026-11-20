import Foundation

// The running record for one bed or plant, built from the journal: which entries belong to it,
// its photos over time, and before-and-after photo pairs around each treatment.

public extension JournalKind {
    /// Things done to a plant or bed whose effect can show up in photos a week or two later.
    /// Watering is left out: it happens too often to compare around.
    var isTreatment: Bool {
        switch self {
        case .feeding, .foliarSpray, .amendment, .mulching, .pruning, .pestOrDisease:
            return true
        default:
            return false
        }
    }
}

/// Whose record is being shown.
public enum RecordScope: Hashable, Sendable {
    /// A bed, with the plants that are in it now (so their entries count even if they were
    /// logged before the plant moved there).
    case bed(UUID, plantIDs: Set<UUID>)
    /// A plant, with the bed it's in now (so entries logged for the whole bed count too).
    case plant(UUID, bedID: UUID?)
}

/// A journal entry that has a photo.
public struct ProgressPhoto: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var day: LocalDay
    public var bedID: UUID?
    public var plantID: UUID?
    /// When the entry was made; orders photos taken on the same day.
    public var created: Date

    public init(id: UUID = UUID(), day: LocalDay, bedID: UUID? = nil, plantID: UUID? = nil, created: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.day = day
        self.bedID = bedID
        self.plantID = plantID
        self.created = created
    }

    /// Same plant, or the same bed when neither photo is of a single plant.
    func sameSubject(as other: ProgressPhoto) -> Bool {
        if plantID != nil || other.plantID != nil { return plantID == other.plantID }
        return bedID == other.bedID
    }

    static func chronological(_ a: ProgressPhoto, _ b: ProgressPhoto) -> Bool {
        a.day != b.day ? a.day < b.day : a.created < b.created
    }
}

/// A treatment with a photo shortly before it and one a week or two after.
public struct TreatmentComparison: Identifiable, Hashable, Sendable {
    public var treatment: JournalInfo
    public var before: ProgressPhoto
    public var after: ProgressPhoto
    /// Other treatments on the same plant or bed between the two photos. They may deserve some
    /// of the credit (or blame), so the app shows them next to the comparison.
    public var alsoApplied: [JournalInfo]

    public var id: UUID { treatment.id }

    public func daysAfterTreatment(calendar: Calendar) -> Int {
        treatment.day.days(to: after.day, calendar: calendar)
    }
}

/// Comparisons for one treatment (by name), newest first.
public struct TreatmentGroup: Identifiable, Hashable, Sendable {
    /// The treatment as it was first written, e.g. "Fish emulsion".
    public var title: String
    public var kind: JournalKind
    public var comparisons: [TreatmentComparison]

    public var id: String { ProgressRecord.groupKey(kind: kind, what: title) }
}

/// What happened to a plant or bed since its previous photo.
public struct PhotoContext: Hashable, Sendable {
    /// The previous photo of the same plant or bed, if any.
    public var previous: ProgressPhoto?
    /// Treatments since then (or in the 30 days before, for the first photo), oldest first.
    public var treatments: [JournalInfo]
}

public enum ProgressRecord {
    /// How far before a treatment a photo still counts as "before".
    public static let maxDaysBefore = 14
    /// Effects of feeding or spraying take a few days to show.
    public static let minDaysAfter = 3
    public static let maxDaysAfter = 30
    /// The "after" photo closest to this many days after the treatment is preferred.
    public static let targetDaysAfter = 10

    // MARK: Membership

    /// Whether a journal entry belongs in a scope's running record. Entries for the whole garden
    /// (no bed, no plant) count only when they're treatments, so a bed's record isn't filled with
    /// every garden-wide note.
    public static func belongs(kind: JournalKind, bedID: UUID?, plantID: UUID?, to scope: RecordScope) -> Bool {
        switch scope {
        case .plant(let id, let currentBed):
            if let plantID = plantID { return plantID == id }
            if let bedID = bedID { return bedID == currentBed }
            return kind.isTreatment
        case .bed(let id, let plantIDs):
            if let plantID = plantID, plantIDs.contains(plantID) { return true }
            if let bedID = bedID { return bedID == id }
            return plantID == nil && kind.isTreatment
        }
    }

    /// Whether a photo belongs in a scope's gallery: a plant's own photos, or for a bed, photos
    /// of the bed and of the plants in it.
    public static func belongs(_ photo: ProgressPhoto, to scope: RecordScope) -> Bool {
        switch scope {
        case .plant(let id, _):
            return photo.plantID == id
        case .bed(let id, let plantIDs):
            if let plantID = photo.plantID, plantIDs.contains(plantID) { return true }
            return photo.bedID == id
        }
    }

    /// Whether a treatment could have affected what a photo shows.
    public static func applies(_ treatment: JournalInfo, to photo: ProgressPhoto) -> Bool {
        if let plantID = treatment.plantID { return plantID == photo.plantID }
        if let bedID = treatment.bedID { return bedID == photo.bedID }
        return true
    }

    // MARK: Before and after

    /// A before-and-after pair for each treatment that has one, newest treatment first.
    ///
    /// "Before" is the latest photo of the same plant or bed on the treatment day or up to
    /// `maxDaysBefore` days earlier. "After" is the photo of that same subject between
    /// `minDaysAfter` and `maxDaysAfter` days later that is closest to `targetDaysAfter`.
    /// When a bed-wide treatment has pairs for several plants, the pair closest to the target
    /// is used.
    public static func comparisons(
        treatments: [JournalInfo],
        photos: [ProgressPhoto],
        calendar: Calendar
    ) -> [TreatmentComparison] {
        let sortedPhotos = photos.sorted(by: ProgressPhoto.chronological)
        let allTreatments = treatments.filter { $0.kind.isTreatment }
        var result: [TreatmentComparison] = []

        for treatment in allTreatments {
            let relevant = sortedPhotos.filter { applies(treatment, to: $0) }
            var best: (before: ProgressPhoto, after: ProgressPhoto, score: Int)?

            for subject in subjects(of: relevant) {
                let mine = relevant.filter { $0.sameSubject(as: subject) }
                guard let pair = pair(around: treatment.day, in: mine, calendar: calendar) else { continue }
                let score = abs(treatment.day.days(to: pair.after.day, calendar: calendar) - targetDaysAfter) * 100
                    + pair.before.day.days(to: treatment.day, calendar: calendar)
                if let current = best, current.score <= score { continue }
                best = (pair.before, pair.after, score)
            }
            guard let chosen = best else { continue }

            let also = allTreatments
                .filter { other in
                    other.id != treatment.id
                        && applies(other, to: chosen.before)
                        && other.day >= chosen.before.day
                        && other.day < chosen.after.day
                }
                .sorted { $0.day < $1.day }
            result.append(TreatmentComparison(treatment: treatment, before: chosen.before, after: chosen.after, alsoApplied: also))
        }

        return result.sorted { a, b in
            a.treatment.day != b.treatment.day ? a.treatment.day > b.treatment.day : a.treatment.id.uuidString < b.treatment.id.uuidString
        }
    }

    /// One representative photo per subject, in first-seen order.
    private static func subjects(of photos: [ProgressPhoto]) -> [ProgressPhoto] {
        var seen: [ProgressPhoto] = []
        for photo in photos where !seen.contains(where: { $0.sameSubject(as: photo) }) {
            seen.append(photo)
        }
        return seen
    }

    /// Photos must be chronological and of one subject.
    private static func pair(
        around day: LocalDay, in photos: [ProgressPhoto], calendar: Calendar
    ) -> (before: ProgressPhoto, after: ProgressPhoto)? {
        let before = photos.last { photo in
            let gap = photo.day.days(to: day, calendar: calendar)
            return gap >= 0 && gap <= maxDaysBefore
        }
        guard let before = before else { return nil }

        var after: ProgressPhoto?
        var afterDistance = Int.max
        for photo in photos {
            let gap = day.days(to: photo.day, calendar: calendar)
            guard gap >= minDaysAfter && gap <= maxDaysAfter else { continue }
            let distance = abs(gap - targetDaysAfter)
            if distance < afterDistance {
                after = photo
                afterDistance = distance
            }
        }
        guard let after = after else { return nil }
        return (before, after)
    }

    // MARK: Grouping

    static func groupKey(kind: JournalKind, what: String) -> String {
        let words = what.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).joined(separator: " ")
        return "\(kind.rawValue)|\(words)"
    }

    /// Comparisons grouped by treatment, so repeated uses of the same thing ("Fish emulsion")
    /// sit together. Groups are ordered by their most recent treatment.
    public static func groups(_ comparisons: [TreatmentComparison]) -> [TreatmentGroup] {
        var order: [String] = []
        var groups: [String: TreatmentGroup] = [:]
        let newestFirst = comparisons.sorted { $0.treatment.day > $1.treatment.day }
        for comparison in newestFirst {
            let what = comparison.treatment.what.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = groupKey(kind: comparison.treatment.kind, what: what)
            if groups[key] == nil {
                order.append(key)
                groups[key] = TreatmentGroup(
                    title: what.isEmpty ? comparison.treatment.kind.displayName : what,
                    kind: comparison.treatment.kind,
                    comparisons: []
                )
            }
            groups[key]?.comparisons.append(comparison)
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: Photo captions

    /// The previous photo of the same plant or bed, and what was done in between. Treatments on
    /// the day of the earlier photo count (the photo is assumed to come first); ones on the day
    /// of this photo don't.
    public static func context(
        for photo: ProgressPhoto,
        photos: [ProgressPhoto],
        treatments: [JournalInfo],
        calendar: Calendar
    ) -> PhotoContext {
        let previous = photos
            .filter { $0.id != photo.id && $0.sameSubject(as: photo) && ProgressPhoto.chronological($0, photo) }
            .sorted(by: ProgressPhoto.chronological)
            .last
        let start = previous?.day ?? photo.day.adding(days: -30, calendar: calendar)
        let between = treatments
            .filter { $0.kind.isTreatment && applies($0, to: photo) && $0.day >= start && $0.day < photo.day }
            .sorted { $0.day < $1.day }
        return PhotoContext(previous: previous, treatments: between)
    }
}
