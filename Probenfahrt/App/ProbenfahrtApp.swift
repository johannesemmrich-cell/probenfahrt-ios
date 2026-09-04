import SwiftUI
import SwiftData

@main
struct ProbenfahrtApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var adminPreview = AdminPreviewStore()
    @State private var devMode = DevModeStore()
    @State private var surveyBadge = SurveySignupBadgeStore()

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .environment(appDelegate.session)
                .environment(appDelegate.unreadMessages)
                .environment(adminPreview)
                .environment(devMode)
                .environment(surveyBadge)
        }
    }
}
