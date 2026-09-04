import UIKit
import UserNotifications

/// Locks the app to portrait at runtime regardless of what
/// UISupportedInterfaceOrientations declares in the bundle — that key now
/// has to list all 4 orientations to satisfy App Store Connect's iPad-
/// multitasking bundle validation, even for this iPhone-only, portrait-only
/// app (see project.yml). This is what actually enforces portrait-only.
///
/// Also owns `session`/`unreadMessages` (instead of ProbenfahrtApp creating
/// its own copies) so the remote-notification callbacks below — which only
/// UIApplicationDelegate receives, not SwiftUI views — can read/update the
/// same instances the UI observes via `.environment(appDelegate.session)`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let session = SessionStore()
    let unreadMessages = UnreadMessagesStore()

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Chat/Umfragen keep working without live push — just no banner/badge
        // until the app is foregrounded again.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            await refreshUnreadBadge()
            completionHandler(.newData)
        }
    }

    @MainActor
    private func refreshUnreadBadge() async {
        guard let userID = session.currentUserID,
              let user = try? await CloudKitUserRepository().user(id: userID) else { return }
        await unreadMessages.refresh(currentUser: user)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Without this, iOS suppresses the banner/sound while the app is in
    /// the foreground — we still want a message to visibly announce itself
    /// even if Probenfahrt happens to already be open on some other tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
