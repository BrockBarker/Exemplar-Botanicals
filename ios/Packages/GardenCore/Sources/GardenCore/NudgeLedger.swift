import Foundation

/// The app's memory of nudges: what is scheduled with the notification center, what already
/// went out, and what the gardener did about it. Saved as JSON between launches.
public struct NudgeLedger: Codable, Sendable {
    /// Upcoming nudges, as handed to the notification center.
    public var scheduled: [Nudge] = []
    /// Nudges that already went out (kept a few days for the Today screen).
    public var delivered: [Nudge] = []
    /// Deliveries, completions and snoozes; drives cooldowns.
    public var history: [NudgeHistory] = []
    /// Ids of nudges the gardener marked done, snoozed or dismissed.
    public var handledIDs: [String] = []

    public init() {}

    /// Moves nudges whose time has come from `scheduled` to `delivered` and records them.
    public mutating func settle(now: Date) {
        let due = scheduled.filter { $0.fireDate <= now }
        guard !due.isEmpty else { prune(now: now); return }
        scheduled.removeAll { $0.fireDate <= now }
        for n in due {
            delivered.append(n)
            history.append(NudgeHistory(dedupeKey: n.dedupeKey, date: n.fireDate))
        }
        prune(now: now)
    }

    /// Plans the next week of nudges and remembers them as scheduled.
    @discardableResult
    public mutating func replan(engine: NudgeEngine, state: GardenState, now: Date, horizonDays: Int = 7) -> [Nudge] {
        settle(now: now)
        let plan = engine.plan(state, history: history, now: now, horizonDays: horizonDays)
        scheduled = plan
        return plan
    }

    /// Nudges that went out recently and still need attention, newest first.
    public func inbox(now: Date, within hours: Double = 36) -> [Nudge] {
        let handled = Set(handledIDs)
        let earliest = now.addingTimeInterval(-hours * 3600)
        return delivered
            .filter { !handled.contains($0.id) && $0.fireDate >= earliest && $0.fireDate <= now }
            .filter { n in n.expires.map { $0 > now } ?? true }
            .sorted { $0.fireDate > $1.fireDate }
    }

    /// Scheduled nudges coming up in the next `hours`, soonest first.
    public func upcoming(now: Date, within hours: Double = 24) -> [Nudge] {
        let latest = now.addingTimeInterval(hours * 3600)
        return scheduled.filter { $0.fireDate > now && $0.fireDate <= latest }.sorted { $0.fireDate < $1.fireDate }
    }

    public func nudge(id: String) -> Nudge? {
        delivered.first { $0.id == id } ?? scheduled.first { $0.id == id }
    }

    /// The gardener did it (or dismissed it). A nudge handled before it fired is cancelled.
    public mutating func markHandled(_ nudge: Nudge, now: Date) {
        if !handledIDs.contains(nudge.id) { handledIDs.append(nudge.id) }
        if scheduled.contains(where: { $0.id == nudge.id }) {
            scheduled.removeAll { $0.id == nudge.id }
            history.append(NudgeHistory(dedupeKey: nudge.dedupeKey, date: now))
        }
    }

    /// Bring this reminder back later.
    public mutating func snooze(_ nudge: Nudge, until: Date, now: Date) {
        if !handledIDs.contains(nudge.id) { handledIDs.append(nudge.id) }
        scheduled.removeAll { $0.id == nudge.id }
        history.append(NudgeHistory(dedupeKey: nudge.dedupeKey, date: now, snoozedUntil: until))
    }

    mutating func prune(now: Date) {
        let deliveredCutoff = now.addingTimeInterval(-4 * 86_400)
        delivered.removeAll { $0.fireDate < deliveredCutoff }
        let historyCutoff = now.addingTimeInterval(-60 * 86_400)
        history.removeAll { $0.date < historyCutoff && ($0.snoozedUntil ?? $0.date) < historyCutoff }
        let keep = Set(delivered.map { $0.id } + scheduled.map { $0.id })
        handledIDs.removeAll { !keep.contains($0) }
    }
}

/// Matches the names the coach uses ("the Sungold", "back bed") to the app's records.
public enum NameMatch {
    /// Index of the best match: exact (ignoring case and a leading "the"), then one name containing the other.
    public static func index(of name: String, in candidates: [String]) -> Int? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }
        let normalized = candidates.map(normalize)
        if let i = normalized.firstIndex(of: target) { return i }
        let containing = normalized.enumerated().filter { !$0.element.isEmpty && ($0.element.contains(target) || target.contains($0.element)) }
        // Prefer the closest length so "tomato" picks "Tomato" over "Tomato bed 2".
        return containing.min { abs($0.element.count - target.count) < abs($1.element.count - target.count) }?.offset
    }

    static func normalize(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["the ", "my "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        return t
    }
}
