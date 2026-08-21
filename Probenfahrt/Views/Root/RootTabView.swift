import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var session
    @Environment(DevModeStore.self) private var devMode

    @State private var currentUser: User?

    private var effectiveAccountKind: AccountKind {
        devMode.isPharmacyModeActive ? .pharmacy : (currentUser?.accountKind ?? .labTeam)
    }

    var body: some View {
        Group {
            if let currentUser {
                if effectiveAccountKind == .pharmacy {
                    pharmacyTabs(for: currentUser)
                } else {
                    labTeamTabs(for: currentUser)
                }
            } else {
                ProgressView()
                    .task { await loadCurrentUser() }
            }
        }
    }

    private func labTeamTabs(for currentUser: User) -> some View {
        TabView {
            SurveysView(currentUser: currentUser)
                .tabItem { Label("Umfragen", systemImage: "list.bullet.clipboard") }

            CalendarView(currentUser: currentUser)
                .tabItem { Label("Kalender", systemImage: "calendar") }

            SamplesListView(currentUser: currentUser)
                .tabItem { Label("Proben", systemImage: "cross.vial") }

            ChatView(currentUser: currentUser)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            SettingsView(currentUser: currentUser, onCurrentUserUpdated: { updated in
                self.currentUser = updated
            })
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }

            if devMode.isPharmacyTabPreviewActive {
                PharmacySamplesView(currentUser: currentUser)
                    .tabItem { Label("Proben (Test)", systemImage: "cross.vial.fill") }
            }
        }
    }

    private func pharmacyTabs(for currentUser: User) -> some View {
        TabView {
            PharmacySamplesView(currentUser: currentUser)
                .tabItem { Label("Proben", systemImage: "cross.vial") }

            SettingsView(currentUser: currentUser, onCurrentUserUpdated: { updated in
                self.currentUser = updated
            })
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }

    private func loadCurrentUser() async {
        guard let id = session.currentUserID else { return }
        let repository = SwiftDataUserRepository(context: modelContext)
        currentUser = try? await repository.user(id: id)
    }
}
