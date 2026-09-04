import UIKit

/// Locks the app to portrait at runtime regardless of what
/// UISupportedInterfaceOrientations declares in the bundle — that key now
/// has to list all 4 orientations to satisfy App Store Connect's iPad-
/// multitasking bundle validation, even for this iPhone-only, portrait-only
/// app (see project.yml). This is what actually enforces portrait-only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}
