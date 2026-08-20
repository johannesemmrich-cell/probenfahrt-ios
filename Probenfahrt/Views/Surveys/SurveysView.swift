import SwiftUI
import SwiftData

struct SurveysView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(AdminPreviewStore.self) private var adminPreview

    @State private var rows: [SurveyDayRow] = []
    @State private var users: [User] = []
    @State private var hasLoadedOnce = false

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty && hasLoadedOnce {
                    ContentUnavailableView("Keine Umfragen", systemImage: "list.bullet.clipboard")
                }
                ForEach(rows) { row in
                    SurveyDayCard(row: row, users: users, currentUser: currentUser) {
                        await toggleSignIn(row: row)
                    }
                }
            }
            .navigationTitle("Umfragen")
            .toolbar {
                if isEffectiveAdmin(user: currentUser, adminPreview: adminPreview) {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Vergangen") {
                            PastSurveysView(currentUser: currentUser)
                        }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            users = try await userRepository.allUsers(inGroup: groupID)
            let dates = SurveyWeekWindow.upcomingDates(from: .now)
            guard let start = dates.first, let end = dates.last else { return }
            let days = try await surveyRepository.surveyDays(from: start, to: end, groupID: groupID)
            var newRows: [SurveyDayRow] = []
            for day in days {
                let entries = try await surveyRepository.entries(forDayID: day.id)
                newRows.append(SurveyDayRow(day: day, entries: entries))
            }
            rows = newRows
        } catch {
            rows = []
        }
        hasLoadedOnce = true
    }

    private func toggleSignIn(row: SurveyDayRow) async {
        let isSignedIn = row.entries.contains { $0.userID == currentUser.id }
        do {
            if isSignedIn {
                try await surveyRepository.signOut(userID: currentUser.id, dayID: row.day.id)
            } else {
                try await surveyRepository.signIn(userID: currentUser.id, dayID: row.day.id)
            }
            await load()
        } catch {
            // Transient failure — next pull-to-refresh resyncs.
        }
    }
}
