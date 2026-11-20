import Foundation
import UserNotifications
import GardenCore

/// Hands the planned nudges to iOS as local notifications. Nothing is sent from a server:
/// the phone plans the next week from the forecast and replans whenever the app refreshes.
@MainActor
enum NotificationScheduler {
    static let nudgeCategory = "EB_NUDGE"
    static let checkCategory = "EB_CHECK"
    static let doneAction = "EB_DONE"
    static let snoozeAction = "EB_SNOOZE"
    /// Moisture check buttons: "EB_MOIST_dry", "EB_MOIST_moist", ...
    static let moisturePrefix = "EB_MOIST_"
    private static let idPrefix = "eb."

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Remind me in 3 hours", options: [])
        let nudge = UNNotificationCategory(identifier: nudgeCategory, actions: [done, snooze], intentIdentifiers: [], options: [])

        let readings = MoistureReading.allCases.map {
            UNNotificationAction(identifier: moisturePrefix + $0.rawValue, title: $0.displayName, options: [])
        }
        let check = UNNotificationCategory(identifier: checkCategory, actions: readings, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([nudge, check])
    }

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Replaces every pending nudge notification with the new plan.
    static func schedule(_ nudges: [Nudge], enabled: Bool, title: (Nudge) -> String, body: (Nudge) -> String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map { $0.identifier }.filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard enabled else { return }

        let now = Date()
        for nudge in nudges where nudge.fireDate > now {
            let content = UNMutableNotificationContent()
            content.title = title(nudge)
            content.body = body(nudge)
            content.sound = .default
            content.categoryIdentifier = nudge.kind == .moistureCheck ? checkCategory : nudgeCategory
            content.threadIdentifier = nudge.kind.rawValue
            content.userInfo = ["nudgeID": nudge.id]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nudge.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: idPrefix + nudge.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("Couldn't schedule \(nudge.id): \(error)")
            }
        }
    }
}
