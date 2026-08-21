import SwiftUI
import SwiftData

/// Weeks that have fully rolled out of the 2 "aktuell" blocks in SurveysView.
/// Visible to everyone; editing (Ein-/Austragen, Sperren) stays admin-only via
/// `canEditSurveyDay`, enforced by the shared `SurveyDayCard`.
struct PastSurveysView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var rows: [SurveyDayRow] = []
    @State private var users: [User] = []

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    var body: some View {
        List {
            if rows.isEmpty {
                Text("Keine vergangenen Umfragen im Zeitraum.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                // Every row here is, by construction, a past day (see load()),
                // so SurveyDayCard's quick-toggle never renders for it
                // (shouldShowQuickToggle is false for past days regardless of
                // role) — admins instead use its "Verwalten" link. onToggle is
                // consequently unreachable; kept as a no-op to satisfy the
                // shared component's signature rather than forking the view.
                SurveyDayCard(row: row, users: users, currentUser: currentUser) {}
            }
        }
        .navigationTitle("Vergangene Umfragen")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            users = try await userRepository.allUsers(inGroup: groupID)
            guard let range = SurveyWeekWindow.pastRange(from: .now) else { return }
            let days = try await surveyRepository.existingSurveyDays(from: range.start, to: range.end, groupID: groupID)
            var newRows: [SurveyDayRow] = []
            for day in days {
                let entries = try await surveyRepository.entries(forDayID: day.id)
                newRows.append(SurveyDayRow(day: day, entries: entries))
            }
            rows = newRows.sorted { $0.day.date > $1.day.date }
        } catch {
            rows = []
        }
    }
}
