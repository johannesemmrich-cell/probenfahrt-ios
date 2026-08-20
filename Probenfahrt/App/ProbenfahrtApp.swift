import SwiftUI
import SwiftData

@main
struct ProbenfahrtApp: App {
    @State private var session = SessionStore()
    @State private var adminPreview = AdminPreviewStore()
    @State private var samplesAccess = SamplesAccessStore()

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .environment(session)
                .environment(adminPreview)
                .environment(samplesAccess)
        }
    }
}
