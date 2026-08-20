import SwiftUI
import SwiftData

struct SurveyDayDetailView: View {
    let row: SurveyDayRow
    let users: [User]
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(AdminPreviewStore.self) private var adminPreview

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }

    private var names: [String] {
        row.entries
            .compactMap { entry in users.first { $0.id == entry.userID }?.name }
            .sorted()
    }

    var body: some View {
        List {
            Section("Eingetragen") {
                if names.isEmpty {
                    Text("Noch niemand eingetragen").foregroundStyle(.secondary)
                } else {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                    }
                }
            }

            // TODO(Backlog #4): admin-only action, not technically enforced yet —
            // reachable by anyone via the "Als Admin anzeigen" dev toggle.
            if isEffectiveAdmin(user: currentUser, adminPreview: adminPreview) {
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

    private func toggleLock() async {
        let newValue = !row.day.isLocked
        try? await surveyRepository.setLocked(
            newValue,
            reason: newValue ? "Wird an diesem Tag nicht gefahren" : nil,
            dayID: row.day.id
        )
    }
}
