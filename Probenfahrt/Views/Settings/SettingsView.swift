import SwiftUI
import SwiftData

struct SettingsView: View {
    let currentUser: User
    let onCurrentUserUpdated: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var session
    @Environment(AdminPreviewStore.self) private var adminPreview

    @State private var name: String
    @State private var abbreviation: String
    @State private var errorMessage: String?
    @State private var isShowingLeaveConfirmation = false

    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    init(currentUser: User, onCurrentUserUpdated: @escaping (User) -> Void) {
        self.currentUser = currentUser
        self.onCurrentUserUpdated = onCurrentUserUpdated
        _name = State(initialValue: currentUser.name)
        _abbreviation = State(initialValue: currentUser.abbreviation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Name", text: $name)
                    TextField("Kürzel", text: $abbreviation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Speichern") {
                        Task { await saveProfile() }
                    }
                }

                Section {
                    Button("Gruppe verlassen", role: .destructive) {
                        isShowingLeaveConfirmation = true
                    }
                }

                // TODO(Backlog #4): admin-only, not technically enforced yet.
                if isEffectiveAdmin(user: currentUser, adminPreview: adminPreview) {
                    Section("Admin") {
                        NavigationLink("Monatsauswertung (PDF)") {
                            AdminReportView(currentUser: currentUser)
                        }
                    }
                }

                Section("Entwicklung") {
                    Toggle("Als Admin anzeigen", isOn: Binding(
                        get: { adminPreview.isEnabled },
                        set: { adminPreview.isEnabled = $0 }
                    ))
                    Text("Zeigt Admin-Bereiche (vergangene Umfragen, Tag sperren, PDF-Export) unabhängig von der echten Rolle — nur für diesen Prototyp. Echte Rechteprüfung folgt später (Backlog #4).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog(
                "Gruppe wirklich verlassen?",
                isPresented: $isShowingLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Verlassen", role: .destructive) { session.signOut() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    private func saveProfile() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAbbreviation.isEmpty else {
            errorMessage = "Name und Kürzel dürfen nicht leer sein."
            return
        }
        guard let groupID = currentUser.groupID else { return }

        if trimmedAbbreviation.lowercased() != currentUser.abbreviation.lowercased() {
            if let taken = try? await userRepository.isAbbreviationTaken(trimmedAbbreviation, inGroup: groupID), taken {
                errorMessage = "Dieses Kürzel ist schon vergeben."
                return
            }
        }

        try? await userRepository.updateUser(id: currentUser.id, name: trimmedName, abbreviation: trimmedAbbreviation)
        onCurrentUserUpdated(currentUser)
    }
}
