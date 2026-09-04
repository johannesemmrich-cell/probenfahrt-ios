import SwiftUI
import SwiftData

/// Renders immediately so the app is never a blank/frozen-looking screen on
/// launch, then creates the ModelContainer in `.task` — first-launch
/// on-disk store creation can occasionally take a few seconds, and this
/// keeps that off the blocking pre-first-frame path.
struct LaunchGateView: View {
    @State private var container: ModelContainer?

    var body: some View {
        Group {
            if let container {
                RootGateView()
                    .modelContainer(container)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Wird vorbereitet …")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .task {
                    container = PersistenceController.makeContainer()
                    // Fire-and-forget: ensuring the CloudKit test group/demo
                    // fixtures exist is a background convenience, not
                    // something the first frame (or even the onboarding
                    // join-code screen, which takes a few seconds of human
                    // typing anyway) needs to block on.
                    Task { await MockDataSeeder.ensureCloudTestDataIfNeeded() }
                }
            }
        }
    }
}
