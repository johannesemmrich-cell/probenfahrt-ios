import SwiftUI

struct OnboardingContainerView: View {
    private enum Step {
        case code
        case labIdentity
        case pharmacyIdentity
    }

    @Environment(SessionStore.self) private var session
    @Environment(DevModeStore.self) private var devMode

    @State private var code = ""
    @State private var name = ""
    @State private var abbreviation = ""
    @State private var firmName = ""
    @State private var step: Step = .code
    @State private var pendingGroupID: UUID?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isDemoFlow = false

    private var userRepository: UserRepository { CloudKitUserRepository() }
    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .code:
                    codeStep
                case .labIdentity:
                    labIdentityStep
                case .pharmacyIdentity:
                    pharmacyIdentityStep
                }
            }
            .padding(24)
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            PartnerLogoMark()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Firmenlogo")
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Gruppen-Code")
                .font(.title2.bold())
            Text("Gib den Beitrittscode für eure Labor-Gruppe ein — oder den Code, den euch die Apotheke/der Zulieferer genannt hat.")
                .foregroundStyle(.secondary)

            TextField("Beitrittscode", text: $code)
                .textFieldStyle(.roundedBorder)
                // Not .characters: join codes match case-insensitively anyway
                // (resolveJoinCode lowercases), and the Dev-Mode-password
                // bypass needs to accept this field's exact mixed-case input.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            errorText

            Spacer()

            Button {
                Task { await submitCode() }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Weiter").foregroundStyle(.black).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(PartnerBrand.yellow)
            .controlSize(.large)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            Button("Demo-Modus ausprobieren") {
                errorMessage = nil
                isDemoFlow = true
                step = .labIdentity
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(isSubmitting)
        }
    }

    private var labIdentityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wie heißt du?")
                .font(.title2.bold())
            Text(isDemoFlow
                 ? "Optional im Demo-Modus — du kannst auch ohne Namen fortfahren."
                 : "Name und ein eindeutiges Kürzel, unter dem dich das Team wiedererkennt.")
                .foregroundStyle(.secondary)

            TextField("Vollständiger Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)

            TextField("Kürzel (z.B. JE)", text: $abbreviation)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            errorText

            Spacer()

            Button {
                Task { await (isDemoFlow ? joinDemo() : joinAsLabTeam()) }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Beitreten").foregroundStyle(.black).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(PartnerBrand.yellow)
            .controlSize(.large)
            .disabled((!isDemoFlow && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                      || isSubmitting)

            if isDemoFlow {
                Button("Ohne Namen fortfahren") {
                    Task { await joinDemo() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isSubmitting)
            }

            backButton
        }
    }

    private var pharmacyIdentityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wer seid ihr?")
                .font(.title2.bold())
            Text("Der Apotheken- oder Firmenname, unter dem euch das Laborteam im Proben-Tab wiedererkennt.")
                .foregroundStyle(.secondary)

            TextField("Apotheken-/Firmenname", text: $firmName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.organizationName)

            errorText

            Spacer()

            Button {
                Task { await joinAsPharmacy() }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Beitreten").foregroundStyle(.black).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(PartnerBrand.yellow)
            .controlSize(.large)
            .disabled(firmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            backButton
        }
    }

    private var backButton: some View {
        Button("Zurück") {
            step = .code
            code = ""
            pendingGroupID = nil
            errorMessage = nil
            isDemoFlow = false
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func submitCode() async {
        errorMessage = nil
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }

        if DevPassword.matches(trimmedCode) {
            await enterDevBypass()
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let result = try await userRepository.resolveJoinCode(trimmedCode) else {
                errorMessage = "Unbekannter Code. Bitte beim Team nachfragen."
                return
            }
            pendingGroupID = result.group.id
            step = result.accountKind == .pharmacy ? .pharmacyIdentity : .labIdentity
        } catch {
            errorMessage = "Etwas ist schiefgelaufen: \(error.localizedDescription)"
        }
    }

    /// Dev-only shortcut (see BACKLOG): typing the Dev-Mode password into the
    /// join-code field logs straight into the standard app as a reusable
    /// "Entwickler" test user, with Dev Mode already active. Only works
    /// while there are just the two demo join codes.
    private func enterDevBypass() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            guard let result = try await userRepository.resolveJoinCode(MockDataSeeder.testGroupJoinCode) else {
                errorMessage = "Dev-Gruppe nicht gefunden."
                return
            }
            let devAbbreviation = "DEV"
            let existingUsers = try await userRepository.allUsers(inGroup: result.group.id)
            let user: User
            if let existing = existingUsers.first(where: { $0.abbreviation.uppercased() == devAbbreviation }) {
                user = existing
            } else {
                user = try await userRepository.createUser(name: "Entwickler", abbreviation: devAbbreviation, groupID: result.group.id)
            }
            session.setCurrentUser(id: user.id)
            devMode.isActive = true
        } catch {
            errorMessage = "Etwas ist schiefgelaufen: \(error.localizedDescription)"
        }
    }

    private func joinAsLabTeam() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAbbreviation.isEmpty, let groupID = pendingGroupID else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if try await userRepository.isAbbreviationTaken(trimmedAbbreviation, inGroup: groupID) {
                errorMessage = "Dieses Kürzel ist in dieser Gruppe schon vergeben."
                return
            }
            let user = try await userRepository.createUser(name: trimmedName, abbreviation: trimmedAbbreviation, groupID: groupID)
            session.setCurrentUser(id: user.id)
        } catch {
            errorMessage = "Etwas ist schiefgelaufen: \(error.localizedDescription)"
        }
    }

    /// Demo path (see README "Demo-Modus"): skips the join-code step
    /// entirely and always lands in a dedicated, isolated demo TeamGroup —
    /// never the real group real testers join via LABOR2026 — so App-Review
    /// testers can't see or affect real team data. Name/Kürzel are optional;
    /// a generic default is used when left blank so "skip" always works.
    private func joinDemo() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        guard let demoGroup = await MockDataSeeder.ensureDemoGroupExists() else {
            errorMessage = "Demo-Modus ist gerade nicht erreichbar. Bitte später erneut versuchen."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Apple Tester" : trimmedName
        let baseAbbreviation = trimmedAbbreviation.isEmpty ? "AT" : trimmedAbbreviation
        var finalAbbreviation = baseAbbreviation
        do {
            var attempt = 0
            while try await userRepository.isAbbreviationTaken(finalAbbreviation, inGroup: demoGroup.id) {
                attempt += 1
                guard attempt <= 5 else {
                    errorMessage = "Demo-Modus ist gerade stark ausgelastet. Bitte gleich noch einmal versuchen."
                    return
                }
                finalAbbreviation = "\(baseAbbreviation)\(Int.random(in: 100...999))"
            }
            let user = try await userRepository.createUser(name: finalName, abbreviation: finalAbbreviation, groupID: demoGroup.id)
            session.setCurrentUser(id: user.id, isDemo: true)
        } catch {
            errorMessage = "Etwas ist schiefgelaufen: \(error.localizedDescription)"
        }
    }

    private func joinAsPharmacy() async {
        errorMessage = nil
        let trimmedName = firmName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let groupID = pendingGroupID else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let user = try await userRepository.createPharmacyUser(firmName: trimmedName, groupID: groupID)
            _ = try await samplesRepository.findOrCreateLocation(ownerUserID: user.id, groupID: groupID, name: trimmedName)
            session.setCurrentUser(id: user.id)
        } catch {
            errorMessage = "Etwas ist schiefgelaufen: \(error.localizedDescription)"
        }
    }
}
