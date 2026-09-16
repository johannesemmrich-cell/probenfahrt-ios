import SwiftUI

struct MemberDetailView: View {
    private enum StatPeriod: String, CaseIterable {
        case week = "Woche"
        case month = "Monat"
    }

    let user: User
    let currentUser: User
    let onRemoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    @State private var abbreviation: String
    @State private var webPassword: String
    @State private var errorMessage: String?
    @State private var webPasswordErrorMessage: String?
    @State private var allEntries: [SurveyEntryWithDate] = []
    @State private var period: StatPeriod = .week
    @State private var referenceDate = Date.now
    @State private var isShowingRemoveConfirmation = false
    @State private var successPulse = 0

    private var userRepository: UserRepository { CloudKitUserRepository() }
    private var surveyRepository: SurveyRepository { CloudKitSurveyRepository() }

    private var isFullAdmin: Bool { Probenfahrt.isFullAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode) }
    private var isDeveloperOverride: Bool { Probenfahrt.isDeveloperOverride(adminPreview: adminPreview, devMode: devMode) }

    init(user: User, currentUser: User, onRemoved: @escaping () -> Void) {
        self.user = user
        self.currentUser = currentUser
        self.onRemoved = onRemoved
        _abbreviation = State(initialValue: user.abbreviation)
        _webPassword = State(initialValue: WebPasswordEncryption.decrypt(user.webPasswordEncrypted ?? "") ?? "")
    }

    private var periodComponent: Calendar.Component { period == .week ? .weekOfYear : .month }

    private var periodInterval: DateInterval? {
        Calendar.current.dateInterval(of: periodComponent, for: referenceDate)
    }

    private var periodTripCount: Int {
        guard let periodInterval else { return 0 }
        return MemberStatsCalculator.tripCount(for: user.id, entries: allEntries, in: periodInterval)
    }

    private var periodLabel: String {
        switch period {
        case .week: return referenceDate.formatted(.dateTime.week().year().locale(.app))
        case .month: return referenceDate.formatted(.dateTime.month(.wide).year().locale(.app))
        }
    }

    var body: some View {
        Form {
            Section("Profil") {
                LabeledContent("Name", value: user.name)
                if isFullAdmin {
                    TextField("Kürzel", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        // onDisappear only (not also onSubmit) - fires on
                        // every way of leaving this screen and avoids two
                        // independent, unsequenced saves racing each other.
                        .onDisappear { Task { await saveAbbreviation() } }
                } else {
                    LabeledContent("Kürzel", value: user.abbreviation)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                LabeledContent("Beigetreten am", value: user.createdAt.formatted(.dateTime.day().month().year().locale(.app)))
                LabeledContent("Rolle", value: roleLabel)
            }

            if isFullAdmin {
                Section {
                    TextField("Passwort (leer = kein Zugang)", text: $webPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        // onSubmit (Return-Taste) UND onDisappear - ein
                        // Fehler beim Speichern (z.B. fehlende Berechtigung)
                        // muss sichtbar sein, während der Screen noch offen
                        // ist, sonst verpufft die Fehlermeldung auf einem
                        // schon verlassenen Screen. Kein Doppel-Save-Risiko:
                        // saveWebPassword() ist ein No-Op, wenn sich der Wert
                        // seit dem letzten Speichern nicht geändert hat.
                        .onSubmit { Task { await saveWebPassword() } }
                        .onDisappear { Task { await saveWebPassword() } }
                    if let webPasswordErrorMessage {
                        Text(webPasswordErrorMessage).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Web-Zugang")
                } footer: {
                    Text("Mit diesem Passwort kann sich \(user.name) auf app.mediproben.com anmelden, ohne ein Apple-Gerät zu benutzen. Feld leeren und speichern entfernt den Zugang wieder.")
                }
            }

            Section("Fahrten") {
                LabeledContent("Insgesamt", value: "\(MemberStatsCalculator.totalTrips(for: user.id, entries: allEntries))")

                Picker("Zeitraum", selection: $period) {
                    ForEach(StatPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(periodLabel).font(.subheadline)
                    Spacer()
                    Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)

                LabeledContent(
                    period == .week ? "Fahrten diese Woche" : "Fahrten diesen Monat",
                    value: "\(periodTripCount)"
                )
            }

            if isFullAdmin, user.id != currentUser.id, user.role != .admin {
                Section {
                    Toggle("Vice-Admin", isOn: Binding(
                        get: { user.role == .viceAdmin },
                        set: { newValue in Task { await setViceAdmin(newValue) } }
                    ))
                    // Appointing a peer Haupt-Admin (as opposed to unlocking
                    // your own via the Admin-Code field) is a deliberate
                    // developer-only escape hatch, symmetric with "Haupt-
                    // Admin-Status entfernen" below.
                    if isDeveloperOverride {
                        Button("Zum Haupt-Admin machen") {
                            Task { await promoteToHauptAdmin() }
                        }
                    }
                } footer: {
                    Text(isDeveloperOverride
                         ? "Vice-Admin kann fast alles, was ein Admin kann — außer Mitglieder entfernen oder Kürzel ändern. \"Zum Haupt-Admin machen\" ist nur im Entwicklermodus/Admin-Vorschau möglich."
                         : "Vice-Admin kann fast alles, was ein Admin kann — außer Mitglieder entfernen oder Kürzel ändern.")
                }
            }

            // Even a real Haupt-Admin can't strip another Haupt-Admin's role —
            // only the DevMode/Admin-Vorschau escape hatch can, since that's a
            // deliberate developer override, not a normal team action.
            if isDeveloperOverride, user.role == .admin {
                Section {
                    Button("Haupt-Admin-Status entfernen", role: .destructive) {
                        Task { await removeAdminStatus() }
                    }
                } footer: {
                    Text("Nur im Entwicklermodus/Admin-Vorschau möglich — stuft auf Mitglied zurück, auch wenn es der letzte Haupt-Admin ist.")
                }
            }

            if isFullAdmin, user.id != currentUser.id {
                Section {
                    Button("Aus Gruppe entfernen", role: .destructive) {
                        isShowingRemoveConfirmation = true
                    }
                } footer: {
                    Text(isDeveloperOverride
                         ? "Entwicklermodus/Admin-Vorschau: entfernt auch den letzten Haupt-Admin. Vergangene Fahrten bleiben in der Auswertung erhalten."
                         : "Vergangene Fahrten bleiben in der Auswertung erhalten.")
                }
            }
        }
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEntries() }
        .sensoryFeedback(.success, trigger: successPulse)
        .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in newValue != nil }
        .sensoryFeedback(.error, trigger: webPasswordErrorMessage) { _, newValue in newValue != nil }
        .confirmationDialog(
            "\(user.name) wirklich aus der Gruppe entfernen?",
            isPresented: $isShowingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) { Task { await remove() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var roleLabel: String {
        switch user.role {
        case .admin: return "Haupt-Admin"
        case .viceAdmin: return "Vice-Admin"
        case .member: return "Mitglied"
        }
    }

    private func shift(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: periodComponent, value: value, to: referenceDate) {
            referenceDate = newDate
        }
    }

    private func loadEntries() async {
        guard let groupID = user.groupID else { return }
        allEntries = (try? await surveyRepository.allEntriesWithDates(groupID: groupID)) ?? []
    }

    private func saveAbbreviation() async {
        errorMessage = nil
        let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Kürzel darf nicht leer sein."
            abbreviation = user.abbreviation
            return
        }
        guard let groupID = user.groupID else { return }
        if trimmed.lowercased() != user.abbreviation.lowercased() {
            if let taken = try? await userRepository.isAbbreviationTaken(trimmed, inGroup: groupID), taken {
                errorMessage = "Dieses Kürzel ist schon vergeben."
                abbreviation = user.abbreviation
                return
            }
        }
        try? await userRepository.updateUser(id: user.id, name: user.name, abbreviation: trimmed)
    }

    private func saveWebPassword() async {
        webPasswordErrorMessage = nil
        let trimmed = webPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentlyStored = WebPasswordEncryption.decrypt(user.webPasswordEncrypted ?? "") ?? ""
        guard trimmed != currentlyStored else { return }
        do {
            if !trimmed.isEmpty {
                if try await userRepository.isWebPasswordTaken(trimmed, excluding: user.id) {
                    webPasswordErrorMessage = "Dieses Passwort ist schon einem anderen Mitglied zugewiesen."
                    webPassword = currentlyStored
                    return
                }
            }
            try await userRepository.setWebPassword(trimmed, for: user.id)
            successPulse += 1
        } catch {
            // Vorher try? auf beiden Aufrufen - ein echter CloudKit-Fehler
            // (z.B. fehlende Write-Berechtigung, nicht als Queryable
            // markiertes Feld) sah dadurch wie ein stilles Nichtstun statt
            // eines Fehlers aus (von einer unabhängigen Verifikation am
            // 2026-09-15 gefunden).
            webPasswordErrorMessage = "Konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func setViceAdmin(_ isOn: Bool) async {
        do {
            try await userRepository.setRole(id: user.id, role: isOn ? .viceAdmin : .member, bypassLastAdminGuard: false)
            successPulse += 1
        } catch {
            errorMessage = "Änderung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func removeAdminStatus() async {
        do {
            try await userRepository.setRole(id: user.id, role: .member, bypassLastAdminGuard: true)
            successPulse += 1
        } catch {
            errorMessage = "Änderung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func promoteToHauptAdmin() async {
        do {
            try await userRepository.setRole(id: user.id, role: .admin, bypassLastAdminGuard: false)
            successPulse += 1
        } catch {
            errorMessage = "Änderung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func remove() async {
        do {
            try await userRepository.deleteUser(id: user.id, bypassLastAdminGuard: isDeveloperOverride)
            successPulse += 1
            onRemoved()
            dismiss()
        } catch UserRepositoryError.cannotRemoveLastAdmin {
            errorMessage = "Das letzte Admin-Konto der Gruppe kann nicht entfernt werden."
        } catch {
            errorMessage = "Etwas ist schiefgelaufen. Bitte erneut versuchen."
        }
    }
}
