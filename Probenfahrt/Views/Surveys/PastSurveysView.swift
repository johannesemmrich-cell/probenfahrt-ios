import SwiftUI

/// Weeks that have fully rolled out of the 2 "aktuell" blocks in SurveysView,
/// grouped into the same "Fahrplan vom...bis..." week blocks — just further
/// back and without an "Aktuell" badge. Visible to everyone; editing
/// (Ein-/Austragen, Sperren) stays admin-only via `canEditSurveyDay`,
/// enforced by the shared `SurveyDayCard`.
struct PastSurveysView: View {
    let currentUser: User

    @State private var blocks: [SurveyWeekWindow.WeekBlock] = []
    @State private var rowsByBlock: [Date: [SurveyDayRow]] = [:]
    @State private var users: [User] = []
    @State private var hasLoadedOnce = false

    private var surveyRepository: SurveyRepository { CloudKitSurveyRepository() }
    private var userRepository: UserRepository { CloudKitUserRepository() }

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
            let entriesByDayID = Dictionary(
                grouping: try await surveyRepository.entries(forDayIDs: days.map(\.id)),
                by: \.surveyDayID
            )
            var newRowsByBlock: [Date: [SurveyDayRow]] = [:]
            for block in newBlocks {
                let rows = days
                    .filter { day in block.days.contains { Calendar.current.isDate($0, inSameDayAs: day.date) } }
                    .map { day in SurveyDayRow(day: day, entries: entriesByDayID[day.id] ?? []) }
                    .sorted { $0.day.date < $1.day.date }
                newRowsByBlock[block.weekStart] = rows
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
