import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct ExemplarBotanicalsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .modelContainer(app.container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await app.refresh() }
            case .background:
                AppModel.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await AppModel.shared.backgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        return true
    }

    /// Show nudges as banners even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// The gardener tapped a nudge or one of its buttons (Done, Snooze, a moisture reading).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let nudgeID = response.notification.request.content.userInfo["nudgeID"] as? String ?? ""
        Task { @MainActor in
            await AppModel.shared.handleNotification(actionID: action, nudgeID: nudgeID)
            completionHandler()
        }
    }
}
