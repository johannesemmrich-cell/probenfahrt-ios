import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var session

    @State private var currentUser: User?

    var body: some View {
        Group {
            if let currentUser {
                TabView {
                    SurveysView(currentUser: currentUser)
                        .tabItem { Label("Umfragen", systemImage: "list.bullet.clipboard") }

                    CalendarView(currentUser: currentUser)
                        .tabItem { Label("Kalender", systemImage: "calendar") }

                    SamplesGateView(currentUser: currentUser)
                        .tabItem { Label("Proben", systemImage: "cross.vial") }

                    ChatView(currentUser: currentUser)
                        .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                    SettingsView(currentUser: currentUser, onCurrentUserUpdated: { updated in
                        self.currentUser = updated
                    })
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                }
            } else {
                ProgressView()
                    .task { await loadCurrentUser() }
            }
        }
    }

    private func loadCurrentUser() async {
        guard let id = session.currentUserID else { return }
        let repository = SwiftDataUserRepository(context: modelContext)
        currentUser = try? await repository.user(id: id)
    }
}
