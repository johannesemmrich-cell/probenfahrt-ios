import SwiftUI
import SwiftData

@main
struct ProbenfahrtApp: App {
    let container = PersistenceController.makeContainer()
    @State private var session = SessionStore()
    @State private var adminPreview = AdminPreviewStore()
    @State private var samplesAccess = SamplesAccessStore()

    var body: some Scene {
        WindowGroup {
            RootGateView()
                .environment(session)
                .environment(adminPreview)
                .environment(samplesAccess)
        }
        .modelContainer(container)
    }
}
