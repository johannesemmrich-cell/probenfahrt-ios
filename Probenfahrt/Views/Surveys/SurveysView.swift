import SwiftUI

struct SurveysView: View {
    let currentUser: User

    @Environment(DevModeStore.self) private var devMode

    @State private var blocks: [SurveyWeekWindow.WeekBlock] = []
    @State private var rowsByBlock: [Date: [SurveyDayRow]] = [:]
    @State private var users: [User] = []
    @State private var hasLoadedOnce = false

    private var surveyRepository: SurveyRepository { CloudKitSurveyRepository() }
    private var userRepository: UserRepository { CloudKitUserRepository() }

    var body: some View {
        NavigationStack {
            List {
                if blocks.isEmpty && hasLoadedOnce {
                    ContentUnavailableView("Keine Umfragen", systemImage: "list.bullet.clipboard")
                }
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    Section {
                        ForEach(rowsByBlock[block.weekStart] ?? []) { row in
                            SurveyDayCard(row: row, users: users, currentUser: currentUser) {
                                await toggleSignIn(row: row)
                            }
                            .listRowBackground(row.entries.count == 1 ? Color.green.opacity(0.15) : nil)
                        }
                    } header: {
                        FahrplanHeader(block: block, isCurrent: index == 0)
                    }
                }
            }
            .navigationTitle("Umfragen")
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Umfragen", feature: "Wochenblöcke", element: "Liste")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Vergangen") {
                        PastSurveysView(currentUser: currentUser)
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
            let newBlocks = SurveyWeekWindow.currentWeekBlocks(from: .now)
            guard let start = newBlocks.first?.weekStart, let end = newBlocks.last?.weekEnd else { return }
            let days = try await surveyRepository.surveyDays(from: start, to: end, groupID: groupID)
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

    /// Flips the button/highlight immediately instead of waiting on the
    /// CloudKit round trip, then writes in the background — signIn/signOut
    /// is idempotent, so no reload is needed on success. On failure the
    /// optimistic change is rolled back via a real reload.
    private func toggleSignIn(row: SurveyDayRow) async {
        let isSignedIn = row.entries.contains { $0.userID == currentUser.id }
        applyOptimisticToggle(dayID: row.day.id, isSignedIn: isSignedIn)
        do {
            if isSignedIn {
                try await surveyRepository.signOut(userID: currentUser.id, dayID: row.day.id)
            } else {
                try await surveyRepository.signIn(userID: currentUser.id, dayID: row.day.id)
            }
        } catch {
            await load()
        }
    }

    private func applyOptimisticToggle(dayID: UUID, isSignedIn: Bool) {
        for (weekStart, rows) in rowsByBlock {
            guard let index = rows.firstIndex(where: { $0.day.id == dayID }) else { continue }
            var entries = rows[index].entries
            if isSignedIn {
                entries.removeAll { $0.userID == currentUser.id }
            } else {
                entries.append(SurveyEntry(surveyDayID: dayID, userID: currentUser.id, groupID: currentUser.groupID))
            }
            var updatedRows = rows
            updatedRows[index] = SurveyDayRow(day: rows[index].day, entries: entries)
            rowsByBlock[weekStart] = updatedRows
            return
        }
    }
}
