import SwiftUI

struct SettingsView: View {
    let currentUser: User
    let onCurrentUserUpdated: (User) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    @State private var name: String
    @State private var abbreviation: String
    @State private var errorMessage: String?
    @State private var isShowingLeaveConfirmation = false
    @State private var leaveErrorMessage: String?
    @State private var successPulse = 0
    @State private var versionTapCount = 0
    @State private var showDeveloperUnlock = false
    @State private var adminCode = ""
    @State private var adminCodeError: String?
    @State private var isShowingFeatureOnboarding = false

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    private var userRepository: UserRepository { CloudKitUserRepository() }

    private var isAdmin: Bool { isEffectiveAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode) }
    private var isFullAdmin: Bool { Probenfahrt.isFullAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode) }

    private var isPharmacyAccount: Bool {
        currentUser.accountKind == .pharmacy
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
                    if let leaveErrorMessage {
                        Text(leaveErrorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                // TODO(Backlog #2): admin-only, not technically enforced yet.
                if !isPharmacyAccount && isAdmin {
                    Section("Admin") {
                        NavigationLink("Monatsauswertung (PDF)") {
                            AdminReportView(currentUser: currentUser)
                        }
                        NavigationLink("Proben-Auswertung (PDF)") {
                            SamplesReportView(currentUser: currentUser)
                        }
                        NavigationLink("Mitglieder verwalten") {
                            TeamMembersView(currentUser: currentUser)
                        }
                        NavigationLink("Apotheken verwalten") {
                            PharmacyManagementView(currentUser: currentUser)
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
                    Button("Onboarding erneut anzeigen") {
                        isShowingFeatureOnboarding = true
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
                    }

                    versionFooter
                }

                Section("Mehr von Emmrich") {
                    EmmrichBanner()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                }

                if !isPharmacyAccount && currentUser.role != .admin {
                    Section {
                        TextField("Code", text: $adminCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Bestätigen") {
                            Task { await submitAdminCode() }
                        }
                        .disabled(adminCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let adminCodeError {
                            Text(adminCodeError).font(.footnote).foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Code eingeben, um Haupt-Admin-Rechte freizuschalten.")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Einstellungen", feature: "Profil", element: "Formular")
            .sensoryFeedback(.success, trigger: successPulse)
            .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in newValue != nil }
            .sensoryFeedback(.error, trigger: adminCodeError) { _, newValue in newValue != nil }
            .sensoryFeedback(.error, trigger: leaveErrorMessage) { _, newValue in newValue != nil }
            .confirmationDialog(
                "Gruppe wirklich verlassen?",
                isPresented: $isShowingLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Verlassen", role: .destructive) { Task { await leaveGroup() } }
                Button("Abbrechen", role: .cancel) {}
            }
            .sheet(isPresented: $showDeveloperUnlock) {
                DeveloperUnlockSheet(isPresented: $showDeveloperUnlock)
            }
            .fullScreenCover(isPresented: $isShowingFeatureOnboarding) {
                FeatureOnboardingView(accountKind: isPharmacyAccount ? .pharmacy : .labTeam) {
                    isShowingFeatureOnboarding = false
                }
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
                if isFullAdmin {
                    TextField("Kürzel", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Kürzel", value: abbreviation)
                    Text("Dein Kürzel steht fest. Nur der Haupt-Admin kann es noch ändern.")
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
        let trimmedAbbreviation = isFullAdmin
            ? abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            : currentUser.abbreviation
        guard !trimmedName.isEmpty, !trimmedAbbreviation.isEmpty else {
            errorMessage = "Name und Kürzel dürfen nicht leer sein."
            return
        }
        guard let groupID = currentUser.groupID else { return }

        if isFullAdmin, trimmedAbbreviation.lowercased() != currentUser.abbreviation.lowercased() {
            if let taken = try? await userRepository.isAbbreviationTaken(trimmedAbbreviation, inGroup: groupID), taken {
                errorMessage = "Dieses Kürzel ist schon vergeben."
                return
            }
        }

        do {
            try await userRepository.updateUser(id: currentUser.id, name: trimmedName, abbreviation: trimmedAbbreviation)
            successPulse += 1
            onCurrentUserUpdated(currentUser)
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func submitAdminCode() async {
        adminCodeError = nil
        guard AdminCode.matches(adminCode) else {
            adminCodeError = "Falscher Code."
            return
        }
        do {
            try await userRepository.setRole(id: currentUser.id, role: .admin, bypassLastAdminGuard: false)
            adminCode = ""
            successPulse += 1
            onCurrentUserUpdated(currentUser)
        } catch {
            adminCodeError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Mirrors the existing admin "Aus Gruppe entfernen" path
    /// (MemberDetailView.remove → deleteUser) instead of just signing out
    /// locally — otherwise the CloudKit User record lingers forever and
    /// permanently blocks this name/Kürzel from being reused on rejoin
    /// (isAbbreviationTaken checks every record ever created, active or not).
    private func leaveGroup() async {
        leaveErrorMessage = nil
        do {
            try await userRepository.deleteUser(id: currentUser.id, bypassLastAdminGuard: false)
            session.signOut()
        } catch UserRepositoryError.cannotRemoveLastAdmin {
            leaveErrorMessage = "Du bist der letzte Admin der Gruppe. Ernenne zuerst jemand anderen zum Admin, bevor du die Gruppe verlässt."
        } catch {
            leaveErrorMessage = "Gruppe verlassen ist fehlgeschlagen. Bitte erneut versuchen."
        }
    }
}
