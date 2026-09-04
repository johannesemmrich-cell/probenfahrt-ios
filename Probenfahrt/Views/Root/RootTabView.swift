import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DevModeStore.self) private var devMode
    @Environment(UnreadMessagesStore.self) private var unreadMessages
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentUser: User?
    @State private var featureOnboarding = FeatureOnboardingStore()
    @State private var isShowingFeatureOnboarding = false

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
        .fullScreenCover(isPresented: $isShowingFeatureOnboarding) {
            FeatureOnboardingView(accountKind: effectiveAccountKind) {
                featureOnboarding.hasSeenFeatureOnboarding = true
                isShowingFeatureOnboarding = false
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active, let currentUser else { return }
            Task { await unreadMessages.refresh(currentUser: currentUser) }
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
                .badge(unreadMessages.unreadCount)

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
        let repository = CloudKitUserRepository()
        let user = try? await repository.user(id: id)
        guard let user else {
            // The stored session points to a user CloudKit doesn't know
            // about — e.g. a leftover local session from before the
            // User/TeamGroup migration to CloudKit, or an account removed
            // from the group by an admin on another device. Sign out so
            // RootGateView falls back to onboarding instead of leaving this
            // screen stuck on its loading spinner forever.
            session.signOut()
            return
        }
        currentUser = user
        if !featureOnboarding.hasSeenFeatureOnboarding {
            isShowingFeatureOnboarding = true
        }
        await unreadMessages.refresh(currentUser: user)
        if let groupID = user.groupID {
            // Fire-and-forget: (re-)registering push subscriptions is a
            // background convenience, not something the tab UI needs to
            // block on.
            Task { await ChatPushSubscriptions.ensure(groupID: groupID, currentUserID: user.id) }
        }
    }
}
