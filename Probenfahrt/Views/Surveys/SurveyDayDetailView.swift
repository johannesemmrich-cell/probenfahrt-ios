import SwiftUI
import SwiftData

struct SurveyDayDetailView: View {
    let row: SurveyDayRow
    let users: [User]
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    @State private var entries: [SurveyEntry]

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }

    init(row: SurveyDayRow, users: [User], currentUser: User) {
        self.row = row
        self.users = users
        self.currentUser = currentUser
        _entries = State(initialValue: row.entries)
    }

    private var isAdmin: Bool { isEffectiveAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode) }

    private var signedInUserIDs: Set<UUID> {
        Set(entries.compactMap(\.userID))
    }

    private var names: [String] {
        entries
            .compactMap { entry in users.first { $0.id == entry.userID }?.name }
            .sorted()
    }

    private var sortedUsers: [User] {
        users.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if isAdmin {
                // TODO(Backlog #2): admin-only action, not technically enforced yet —
                // reachable by anyone via the "Als Admin anzeigen" dev toggle.
                Section {
                    if sortedUsers.isEmpty {
                        Text("Keine Mitglieder in der Gruppe").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedUsers) { user in
                            Button {
                                Task { await toggleEntry(for: user) }
                            } label: {
                                HStack {
                                    Text(user.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: signedInUserIDs.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(signedInUserIDs.contains(user.id) ? .green : .secondary)
                                }
                            }
                            .disabled(row.day.isLocked)
                        }
                    }
                } header: {
                    Text("Teilnehmer verwalten")
                } footer: {
                    Text(row.day.isLocked
                         ? "Tag ist gesperrt — erst Sperre aufheben, um Teilnehmer zu ändern."
                         : "Tippe auf eine Person, um sie für diesen Tag ein- oder auszutragen.")
                }
            } else {
                Section("Eingetragen") {
                    if names.isEmpty {
                        Text("Noch niemand eingetragen").foregroundStyle(.secondary)
                    } else {
                        ForEach(names, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }

            if isAdmin {
                Section("Admin") {
                    Button(row.day.isLocked ? "Sperre aufheben" : "Tag sperren") {
                        Task { await toggleLock() }
                    }
                    .foregroundStyle(row.day.isLocked ? Color.primary : Color.red)
                }
            }
        }
        .navigationTitle(row.day.date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleEntry(for user: User) async {
        do {
            if signedInUserIDs.contains(user.id) {
                try await surveyRepository.signOut(userID: user.id, dayID: row.day.id)
            } else {
                try await surveyRepository.signIn(userID: user.id, dayID: row.day.id)
            }
            entries = try await surveyRepository.entries(forDayID: row.day.id)
        } catch {
            // Transient failure — reopening the screen resyncs.
        }
    }

    private func toggleLock() async {
        let newValue = !row.day.isLocked
        try? await surveyRepository.setLocked(
            newValue,
            reason: newValue ? "Wird an diesem Tag nicht gefahren" : nil,
            dayID: row.day.id
        )
    }
}
