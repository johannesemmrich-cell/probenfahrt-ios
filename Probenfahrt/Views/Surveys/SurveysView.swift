import SwiftUI
import SwiftData

struct SurveysView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(DevModeStore.self) private var devMode

    @State private var blocks: [SurveyWeekWindow.WeekBlock] = []
    @State private var rowsByBlock: [Date: [SurveyDayRow]] = [:]
    @State private var users: [User] = []
    @State private var hasLoadedOnce = false

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

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
                        }
                    } header: {
                        fahrplanHeader(for: block, isCurrent: index == 0)
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

    private func fahrplanHeader(for block: SurveyWeekWindow.WeekBlock, isCurrent: Bool) -> some View {
        HStack {
            Text("Fahrplan vom \(block.weekStart.formatted(.dateTime.weekday(.wide).day().month().locale(.app))) bis \(block.weekEnd.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))")
            if isCurrent {
                Spacer()
                Text("Aktuell")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            users = try await userRepository.allUsers(inGroup: groupID)
            let newBlocks = SurveyWeekWindow.currentWeekBlocks(from: .now)
            guard let start = newBlocks.first?.weekStart, let end = newBlocks.last?.weekEnd else { return }
            let days = try await surveyRepository.surveyDays(from: start, to: end, groupID: groupID)
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
