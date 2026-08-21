import SwiftUI
import SwiftData

struct SettingsView: View {
    let currentUser: User
    let onCurrentUserUpdated: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var session
    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    @State private var name: String
    @State private var abbreviation: String
    @State private var errorMessage: String?
    @State private var isShowingLeaveConfirmation = false
    @State private var versionTapCount = 0
    @State private var showDeveloperUnlock = false

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }
    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    private var isAdmin: Bool { isEffectiveAdmin(user: currentUser, adminPreview: adminPreview) }

    /// Effective, not just the real account — DevMode's full "Apotheken-Modus"
    /// switch (see RootTabView) shrinks Einstellungen the same way it shrinks
    /// the tab bar, so the way back (Entwicklung-Section) stays reachable.
    private var isPharmacyAccount: Bool {
        devMode.isPharmacyModeActive || currentUser.accountKind == .pharmacy
    }

    init(currentUser: User, onCurrentUserUpdated: @escaping (User) -> Void) {
        self.currentUser = currentUser
        self.onCurrentUserUpdated = onCurrentUserUpdated
        _name = State(initialValue: currentUser.name)
        _abbreviation = State(initialValue: currentUser.abbreviation)
    }

    var body: some View {
        NavigationStack {
            Form {
                profilSection

                Section {
                    Button("Gruppe verlassen", role: .destructive) {
                        isShowingLeaveConfirmation = true
                    }
                }

                // TODO(Backlog #2): admin-only, not technically enforced yet.
                if !isPharmacyAccount && isAdmin {
                    Section("Admin") {
                        NavigationLink("Monatsauswertung (PDF)") {
                            AdminReportView(currentUser: currentUser)
                        }
                        NavigationLink("Mitglieder verwalten") {
                            TeamMembersView(currentUser: currentUser)
                        }
                    }
                }

                Section("Über") {
                    NavigationLink("Über Probenfahrt") {
                        AboutView()
                    }
                    NavigationLink("Datenschutz") {
                        PrivacyView()
                    }
                }

                Section("Entwicklung") {
                    if !isPharmacyAccount {
                        Toggle("Als Admin anzeigen", isOn: Binding(
                            get: { adminPreview.isEnabled },
                            set: { adminPreview.isEnabled = $0 }
                        ))
                        Text("Zeigt Admin-Bereiche (vergangene Umfragen bearbeiten, Tag sperren, PDF-Export, Mitglieder verwalten) unabhängig von der echten Rolle — nur für diesen Prototyp. Echte Rechteprüfung folgt später (Backlog #2).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if devMode.isActive {
                        NavigationLink("Entwicklermodus") {
                            DeveloperModeView()
                        }

                        if !isPharmacyAccount {
                            Toggle("Proben-Tab (Apotheke) als Extra-Tab", isOn: Binding(
                                get: { devMode.isPharmacyTabPreviewActive },
                                set: { newValue in
                                    devMode.isPharmacyTabPreviewActive = newValue
                                    Task { await cleanupPharmacyPreviewLocationIfNeeded() }
                                }
                            ))
                        }

                        Button(devMode.isPharmacyModeActive ? "Zu Standard-Modus wechseln" : "Zu Apotheken-Modus wechseln") {
                            devMode.isPharmacyModeActive.toggle()
                            Task { await cleanupPharmacyPreviewLocationIfNeeded() }
                        }
                    }

                    versionFooter
                }

                Section("Mehr von Emmrich") {
                    EmmrichBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("Einstellungen")
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Einstellungen", feature: "Profil", element: "Formular")
            .confirmationDialog(
                "Gruppe wirklich verlassen?",
                isPresented: $isShowingLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Verlassen", role: .destructive) { session.signOut() }
                Button("Abbrechen", role: .cancel) {}
            }
            .sheet(isPresented: $showDeveloperUnlock) {
                DeveloperUnlockSheet(isPresented: $showDeveloperUnlock)
            }
        }
    }

    @ViewBuilder
    private var profilSection: some View {
        Section("Profil") {
            if isPharmacyAccount {
                LabeledContent("Firmenname", value: currentUser.name)
            } else {
                TextField("Name", text: $name)
                if isAdmin {
                    TextField("Kürzel", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Kürzel", value: abbreviation)
                    Text("Dein Kürzel steht fest. Nur ein Admin kann es noch ändern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                Button("Speichern") {
                    Task { await saveProfile() }
                }
            }
        }
    }

    private var versionFooter: some View {
        Button {
            handleVersionTap()
        } label: {
            HStack(spacing: 6) {
                Spacer()
                Text("Probenfahrt \(appVersion) (\(buildNumber))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if devMode.isActive {
                    Text("DEV")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Once neither DevMode pharmacy-preview mechanism is active anymore,
    /// remove the SampleLocation they created under this real lab-team
    /// user's identity — otherwise it lingers forever, unfiltered, in the
    /// whole team's real Proben tab. Pharmacy accounts never see these
    /// toggles, so any location owned by a labTeam user's id can only have
    /// come from one of these two previews.
    private func cleanupPharmacyPreviewLocationIfNeeded() async {
        guard !devMode.isPharmacyTabPreviewActive, !devMode.isPharmacyModeActive else { return }
        guard currentUser.accountKind == .labTeam else { return }
        try? await samplesRepository.deleteLocationIfOwned(by: currentUser.id)
    }

    private func handleVersionTap() {
        versionTapCount += 1
        if versionTapCount >= 5 {
            versionTapCount = 0
            showDeveloperUnlock = true
        }
    }

    private func saveProfile() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbreviation = isAdmin
            ? abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            : currentUser.abbreviation
        guard !trimmedName.isEmpty, !trimmedAbbreviation.isEmpty else {
            errorMessage = "Name und Kürzel dürfen nicht leer sein."
            return
        }
        guard let groupID = currentUser.groupID else { return }

        if isAdmin, trimmedAbbreviation.lowercased() != currentUser.abbreviation.lowercased() {
            if let taken = try? await userRepository.isAbbreviationTaken(trimmedAbbreviation, inGroup: groupID), taken {
                errorMessage = "Dieses Kürzel ist schon vergeben."
                return
            }
        }

        try? await userRepository.updateUser(id: currentUser.id, name: trimmedName, abbreviation: trimmedAbbreviation)
        onCurrentUserUpdated(currentUser)
    }
}
