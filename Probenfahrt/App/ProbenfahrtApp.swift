import SwiftUI
import SwiftData

@main
struct ProbenfahrtApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var adminPreview = AdminPreviewStore()
    @State private var devMode = DevModeStore()

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .environment(session)
                .environment(adminPreview)
                .environment(devMode)
        }
    }
}
