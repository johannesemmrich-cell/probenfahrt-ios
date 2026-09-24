import SwiftUI

struct RootTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(UnreadMessagesStore.self) private var unreadMessages
    @Environment(SurveySignupBadgeStore.self) private var surveyBadge
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentUser: User?
    @State private var featureOnboarding = FeatureOnboardingStore()
    @State private var isShowingFeatureOnboarding = false
    @State private var updateInfo: AppUpdateInfo?

    private var effectiveAccountKind: AccountKind {
        currentUser?.accountKind ?? .labTeam
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
        .overlay(alignment: .top) {
            if let updateInfo {
                UpdateAvailableBanner(info: updateInfo) { self.updateInfo = nil }
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active, let currentUser else { return }
            Task { await unreadMessages.refresh(currentUser: currentUser) }
            Task { await surveyBadge.refresh(currentUser: currentUser) }
            Task { updateInfo = await AppUpdateChecker.checkForUpdate() }
        }
    }

    private func labTeamTabs(for currentUser: User) -> some View {
        TabView {
            SurveysView(currentUser: currentUser)
                .tabItem { Label("Umfragen", systemImage: "list.bullet.clipboard") }
                .badge(surveyBadge.count)

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
        if !session.isDemoSession, let groupID = user.groupID {
            // Self-heal: a device could have a demo session created by a
            // build from before isDemoSession existed (pre commit 1c58e64)
            // — an in-place update would otherwise silently lose the "Als
            // Admin anzeigen" toggle for it. The demo group id is normally
            // cached by joinDemo() itself; resolve it once, lazily, only if
            // still missing (e.g. this session predates that caching too),
            // so this never costs a CloudKit round-trip on repeat launches.
            if UserDefaults.standard.string(forKey: MockDataSeeder.demoGroupIDKey) == nil {
                _ = await MockDataSeeder.ensureDemoGroupExists()
            }
            if let cachedDemoGroupID = UserDefaults.standard.string(forKey: MockDataSeeder.demoGroupIDKey),
               groupID.uuidString == cachedDemoGroupID {
                session.setCurrentUser(id: user.id, isDemo: true)
            }
        }
        if !featureOnboarding.hasSeenFeatureOnboarding {
            isShowingFeatureOnboarding = true
        }
        await unreadMessages.refresh(currentUser: user)
        await surveyBadge.refresh(currentUser: user)
        updateInfo = await AppUpdateChecker.checkForUpdate()
        if let groupID = user.groupID {
            // Fire-and-forget: (re-)registering push subscriptions is a
            // background convenience, not something the tab UI needs to
            // block on.
            Task { await ChatPushSubscriptions.ensure(groupID: groupID, currentUserID: user.id) }
            if user.accountKind == .labTeam {
                // Only the lab team sees the Proben overview — pharmacy
                // accounts report their own status but never see the rest
                // of the team's, so a "Proben da" push wouldn't mean
                // anything to them.
                Task { await SamplesPushSubscriptions.ensure(groupID: groupID, currentUserID: user.id) }
            }
        }
    }
}

private struct UpdateAvailableBanner: View {
    let info: AppUpdateInfo
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Update verfügbar")
                    .font(.subheadline.weight(.semibold))
                Text("Version \(info.availableVersion) ist im App Store bereit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Aktualisieren") {
                openURL(info.appStoreURL)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: info.availableVersion)
    }
}
