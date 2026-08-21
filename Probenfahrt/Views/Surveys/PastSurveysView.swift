import SwiftUI
import SwiftData

/// Weeks that have fully rolled out of the 2 "aktuell" blocks in SurveysView,
/// grouped into the same "Fahrplan vom...bis..." week blocks — just further
/// back and without an "Aktuell" badge. Visible to everyone; editing
/// (Ein-/Austragen, Sperren) stays admin-only via `canEditSurveyDay`,
/// enforced by the shared `SurveyDayCard`.
struct PastSurveysView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var blocks: [SurveyWeekWindow.WeekBlock] = []
    @State private var rowsByBlock: [Date: [SurveyDayRow]] = [:]
    @State private var users: [User] = []
    @State private var hasLoadedOnce = false

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    private var nonEmptyBlocks: [SurveyWeekWindow.WeekBlock] {
        blocks.filter { !(rowsByBlock[$0.weekStart] ?? []).isEmpty }
    }

    var body: some View {
        List {
            if nonEmptyBlocks.isEmpty && hasLoadedOnce {
                Text("Keine vergangenen Umfragen im Zeitraum.")
                    .foregroundStyle(.secondary)
            }
            ForEach(nonEmptyBlocks) { block in
                Section {
                    ForEach(rowsByBlock[block.weekStart] ?? []) { row in
                        // Every row here is, by construction, a past day (see
                        // load()), so SurveyDayCard's quick-toggle never
                        // renders for it (shouldShowQuickToggle is false for
                        // past days regardless of role) — admins instead use
                        // its "Verwalten" link. onToggle is consequently
                        // unreachable; kept as a no-op to satisfy the shared
                        // component's signature rather than forking the view.
                        SurveyDayCard(row: row, users: users, currentUser: currentUser) {}
                    }
                } header: {
                    FahrplanHeader(block: block)
                }
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
            let newBlocks = SurveyWeekWindow.pastWeekBlocks(from: .now)
            guard let start = newBlocks.last?.weekStart, let end = newBlocks.first?.weekEnd else { return }
            let days = try await surveyRepository.existingSurveyDays(from: start, to: end, groupID: groupID)
            var newRowsByBlock: [Date: [SurveyDayRow]] = [:]
            for block in newBlocks {
                var rows: [SurveyDayRow] = []
                for day in days where block.days.contains(where: { Calendar.current.isDate($0, inSameDayAs: day.date) }) {
                    let entries = try await surveyRepository.entries(forDayID: day.id)
                    rows.append(SurveyDayRow(day: day, entries: entries))
                }
                newRowsByBlock[block.weekStart] = rows.sorted { $0.day.date < $1.day.date }
            }
            blocks = newBlocks
            rowsByBlock = newRowsByBlock
        } catch {
            blocks = []
            rowsByBlock = [:]
        }
        hasLoadedOnce = true
    }
}
