import SwiftUI
import SwiftData

/// Admin-only: survey days before today, beyond the normal rolling window.
/// TODO(Backlog #4): not technically access-controlled yet — reachable by
/// anyone who reaches this screen via the "Als Admin anzeigen" dev toggle.
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
                NavigationLink {
                    SurveyDayDetailView(row: row, users: users, currentUser: currentUser)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.day.date.formatted(.dateTime.weekday(.wide).day().month().year().locale(.app)))
                            .font(.headline)
                        Text("\(row.entries.count) eingetragen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Vergangene Umfragen")
        .task { await load() }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            users = try await userRepository.allUsers(inGroup: groupID)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            guard let start = calendar.date(byAdding: .day, value: -21, to: today),
                  let end = calendar.date(byAdding: .day, value: -1, to: today) else { return }
            let days = try await surveyRepository.existingSurveyDays(from: start, to: end, groupID: groupID)
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
