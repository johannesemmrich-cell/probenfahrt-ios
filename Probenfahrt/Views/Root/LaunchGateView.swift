import SwiftUI
import SwiftData

/// Renders immediately so the app is never a blank/frozen-looking screen on
/// launch, then creates the ModelContainer + seeds mock data in `.task` —
/// first-launch on-disk store creation can occasionally take a few seconds,
/// and this keeps that off the blocking pre-first-frame path.
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
                }
            }
        }
    }
}
